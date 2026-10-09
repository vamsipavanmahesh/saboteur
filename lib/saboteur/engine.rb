# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require "json"
require "prism"

module Saboteur
  # Orchestrates one run: boot, find subjects, coverage map, then per subject
  # the neutral check, coarse mutants and fine mutants.
  class Engine
    # A subject that passed its neutral check, with what its mutants need.
    Plan = Data.define(:subject, :runner, :tests, :timeout, :map)

    attr_reader :config, :hooks

    def initialize(config, err: $stderr)
      @config = config
      @err = err
      @hooks = Hooks.new
      @warnings = []
      @invalid = 0
      @root = File.realpath(config.root)
    end

    def call
      refuse_recursion!
      started = monotonic
      ignore_list = IgnoreList.load(config.path("ignore_file"))
      load_hooks
      rails = Rails.new(config, hooks) if config["rails"]
      rails&.before_boot
      hooks.run(:before_boot)
      boot
      rails&.after_boot
      hooks.run(:after_boot)

      files = config.included_files
      subjects = select_subjects(find_subjects(files))
      results = subjects.empty? ? [] : mutate(subjects, files)
      @warnings.concat(ignore_list.apply(results))
      Report.new(results: results, subjects: subjects, wall_time: monotonic - started, root: @root,
                 invalid_mutations: @invalid, warnings: @warnings)
    end

    private

    # A test suite that (perhaps only under a mutant) starts a saboteur run
    # would otherwise run saboteur inside a saboteur child, recursively.
    def refuse_recursion!
      return unless ENV[Supervisor::CHILD_ENV]

      raise Error, "refusing to start: this process is a saboteur child (#{Supervisor::CHILD_ENV} is set). " \
                   "A test is running saboteur itself; stub it."
    end

    def supervisor(memory_factor: 1)
      Supervisor.new(limits: Supervisor::Limits.new(max_memory_mb: config["max_memory_mb"] * memory_factor,
                                                    max_processes: config["max_processes"]))
    end

    # --- boot -------------------------------------------------------------

    def load_hooks
      Saboteur.current_hooks = hooks
      config["hooks"].each { |file| load File.expand_path(file, @root) }
    ensure
      Saboteur.current_hooks = nil
    end

    def boot
      config["require"].each { |file| require File.expand_path(file, @root) }
      @integration = Integration.fetch(config["integration"]).new(config)
      @integration.setup
    end

    # --- subjects -----------------------------------------------------------

    def find_subjects(files)
      finder = SubjectFinder.new
      files.flat_map do |file|
        parsed = finder.call(file)
        parsed.errors.first(1).each { |message| @warnings << "#{relative(file)} does not parse: #{message}" }
        parsed.subjects
      end
    end

    def select_subjects(subjects)
      patterns = config["subjects"]
      subjects = subjects.select { |subject| patterns.any? { |pattern| subject_match?(subject.id, pattern) } } if
        patterns.any?
      return subjects unless config["since"]

      changed = GitDiff.changed_lines(config["since"], root: @root)
      changed = changed.transform_keys { |file| CoverageMap.canonical(file) }
      subjects.select do |subject|
        lines = changed[subject.file]
        lines&.any? { |line| subject.contains_line?(line) }
      end
    end

    def subject_match?(id, pattern)
      id == pattern || %w[# . ::].any? { |separator| id.start_with?("#{pattern}#{separator}") }
    end

    # --- mutation loop ------------------------------------------------------

    def mutate(subjects, files)
      map = coverage_map(files)
      @err.puts "saboteur: #{subjects.size} subjects, #{map.tests.size} tests in coverage map"
      warn_about_threads
      runner = Runner.new(integration: @integration, reevaluator: reevaluator, hooks: hooks, supervisor: supervisor)
      sources = build_sources
      subjects.flat_map { |subject| process(subject, map, runner, sources) }
    end

    def process(subject, map, runner, sources)
      candidates = candidates_for(subject, sources)
      return [] if candidates.empty?

      reason = subject.skip_reason || load_problem(subject)
      return skip_all(candidates, subject, reason) if reason

      tests = map.tests_for(subject)
      return skip_all(candidates, subject, "no coverage") if tests.empty?

      timeout = neutral_check(subject, runner, tests)
      return skip_all(candidates, subject, "baseline failure", covered_by: tests) unless timeout

      run_candidates(Plan.new(subject:, runner:, tests:, timeout:, map:), candidates)
    end

    # Runs the subject's tests against the re-evaluated, unchanged method.
    # Returns the per-mutant timeout, or nil when the tests do not pass.
    def neutral_check(subject, runner, tests)
      baseline = runner.run(subject: subject, text: subject.source, test_ids: tests,
                            timeout: config["baseline_timeout"])
      note_leftovers(subject, "neutral check", baseline)
      return [config["timeout_factor"] * baseline.runtime, config["timeout_min"]].max if baseline.status == :survived

      detail = baseline.message.to_s.lines.first&.strip || "failed: #{baseline.failed_ids.first(3).join(', ')}"
      @warnings << "#{subject.id}: neutral check #{baseline.status}, #{detail}"
      nil
    end

    def run_candidates(plan, candidates)
      coarse, fine = candidates.partition { |mutation, _| mutation.coarse }
      results = coarse.map { |mutation, text| execute(plan, mutation, text) }
      if results.any?(&:survived?)
        return results + skip_all(fine, plan.subject, "coarse mutant survived", covered_by: plan.tests)
      end

      results + fine.map { |mutation, text| execute(plan, mutation, text) }
    end

    def execute(plan, mutation, text)
      tests = tests_for_mutation(plan, mutation)
      return skip_all([[mutation, text]], plan.subject, "no coverage").first if tests.empty?

      outcome = plan.runner.run(subject: plan.subject, text: text, test_ids: tests, timeout: plan.timeout,
                                mutation: mutation)
      result = MutantResult.new(subject: plan.subject, mutation: mutation, status: outcome.status,
                                mutated_source: text, reason: outcome.message, runtime: outcome.runtime,
                                killed_by: outcome.failed_ids, covered_by: tests)
      note_leftovers(plan.subject, "#{mutation.operator} #{result.digest}", outcome)
      progress(result)
      result
    end

    # Coarse mutants replace the whole body: every test of the method. Fine
    # mutants: only the tests that executed the edited statement, kept in
    # the order the neutral check ran them.
    def tests_for_mutation(plan, mutation)
      return plan.tests if mutation.coarse

      line_numbers = mutation.edits.flat_map { |edit| plan.subject.lines_for(edit) }.uniq
      plan.tests & plan.map.tests_for_lines(plan.subject.file, line_numbers)
    end

    def note_leftovers(subject, what, outcome)
      return if outcome.leftovers.empty?

      @warnings << "#{subject.id} #{what}: killed #{outcome.leftovers.size} process(es) it left running"
    end

    def skip_all(candidates, subject, reason, covered_by: [])
      candidates.map do |mutation, text|
        MutantResult.new(subject: subject, mutation: mutation, status: :skipped, mutated_source: text,
                         reason: reason, covered_by: covered_by)
      end
    end

    def progress(result)
      mark = { killed: ".", survived: "S", timeout: "T", error: "E" }.fetch(result.status, "?")
      @err.print(mark)
      @err.flush
    end

    # [[mutation, mutated_text]], coarse first, valid and de-duplicated.
    def candidates_for(subject, sources)
      return [] unless parses?(subject.source)

      seen = Set[subject.source]
      list = sources.flat_map { |source| source.mutations_for(subject) }.filter_map do |mutation|
        text = subject.apply(mutation.edits)
        next if seen.include?(text)

        seen << text
        unless parses?(text)
          @invalid += 1
          next
        end

        [mutation, text]
      rescue ArgumentError => e
        @warnings << "#{subject.id}: dropped #{mutation.source} mutation: #{e.message}"
        nil
      end
      list.sort_by.with_index { |(mutation, _), index| [mutation.coarse ? 0 : 1, index] }
    end

    def parses?(text)
      Prism.parse(text).success?
    end

    # The method saboteur would redefine must be the one Ruby is running.
    def load_problem(subject)
      owner = reevaluator.resolve_owner(subject)
      target = subject.singleton ? owner.singleton_class : owner
      method = own_method(target, subject.name)
      return "method not loaded" unless method

      file, line = method.source_location
      return nil if file && CoverageMap.canonical(file) == subject.file && line == subject.start_line

      "shadowed definition (runtime method at #{file}:#{line})"
    rescue Error => e
      "owner not loaded: #{e.message}"
    end

    def own_method(target, name)
      return nil unless target.method_defined?(name) || target.private_method_defined?(name)

      method = target.instance_method(name)
      method = method.super_method while method && method.owner != target
      method
    end

    # --- coverage ----------------------------------------------------------

    def coverage_map(files)
      key = CoverageMap.cache_key(files: files + @integration.test_files + lockfiles, extra: cache_inputs)
      path = File.join(config.path("cache_dir"), "coverage-#{key}.json")
      cached = config["cache"] ? CoverageMap.load(path) : nil
      return cached if cached

      map = build_coverage_map(files)
      map.save(path)
      map
    end

    def cache_inputs
      JSON.generate(%w[integration require rspec_args test_files rails].to_h { |k| [k, config[k]] })
    end

    def lockfiles
      %w[Gemfile.lock gems.locked].map { |file| File.join(@root, file) }.select { |file| File.file?(file) }
    end

    def build_coverage_map(files)
      unless Coverage.respond_to?(:state) && Coverage.state == :suspended
        raise Error, "Coverage is #{Coverage.state}; saboteur must set it up before the app loads. " \
                     "Run through the saboteur executable and disable SimpleCov for the run."
      end

      @err.puts "saboteur: building coverage map (runs the whole suite once)"
      result = supervisor(memory_factor: 4).run(timeout: config["coverage_timeout"]) do |writer|
        coverage_child(writer, files)
      end
      raise Error, "coverage map build stopped: #{result.detail}" if result.stop

      data = JSON.parse(result.payload.empty? ? '{"error":"coverage child died"}' : result.payload)
      raise Error, "coverage map build failed: #{data['error']}" if data["error"]

      CoverageMap.from_json(result.payload)
    end

    def coverage_child(writer, files)
      $stdout.reopen(File::NULL, "w")
      $stderr.reopen($stdout)
      hooks.run(:after_fork)
      started = monotonic
      recorder = CoverageMap::Recorder.new(files)
      recorder.start
      @integration.run_all(recorder)
      writer.write(recorder.result(build_seconds: monotonic - started).to_json)
      writer.close
    rescue Exception => e # rubocop:disable Lint/RescueException
      writer.write(JSON.generate(error: "#{e.class}: #{e.message}"))
      exit!(1)
    end

    # --- helpers ----------------------------------------------------------

    def reevaluator
      @reevaluator ||= Reevaluator.new(config["reeval"])
    end

    def build_sources
      config["sources"].map do |entry|
        next MutationSource::Builtin.new(arid: config["arid"]) if entry == "builtin"

        file, const = entry.split(":", 2)
        raise Error, "mutation source #{entry.inspect} must be builtin or path.rb:ClassName" unless const

        require File.expand_path(file, @root)
        Object.const_get(const).new
      end
    end

    def warn_about_threads
      others = Thread.list.size - 1
      return unless others.positive?

      @warnings << "#{others} other thread(s) alive at fork time; they do not run in children"
    end

    def relative(file)
      file.delete_prefix("#{@root}/")
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
