# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "replay"
require_relative "mutation_source/hazard_guard"
require_relative "baseline/run_evidence"

module Saboteur
  # A single-use instance runs one pipeline: boot the target, select subjects, fetch the
  # coverage map, then schedule each subject's mutants. The parts live in
  # engine/; this class only wires them together.
  class Engine
    # Everything besides sources and tests that can change a verdict.
    VERDICT_INPUTS = %w[integration require rspec_args rails reeval sources operators arid timeout_factor timeout_min
                        max_memory_mb max_processes seed tests whole_file].freeze

    attr_reader :config, :hooks
    # The specs --guess-tests narrowed the run to, or nil when it did not.
    attr_reader :guessed_tests

    def initialize(config, err: $stderr, digest: nil, capture_evidence: false, evidence_files: [])
      @config = config
      @hooks = Hooks.new
      @diagnostics = Diagnostics.new(err)
      @root = File.realpath(config.root)
      @skipped_subjects = {}
      @replay = Replay.new(digest: digest) if digest
      if capture_evidence && (digest || config["since"] || config["incremental"])
        raise ConfigError, "baseline evidence requires fresh whole-scope execution: no since, replay or incremental"
      end

      @capture_evidence = capture_evidence
      @evidence_files = evidence_files
      @stable_suite = false
    end

    def call
      Boot.refuse_recursion!
      refuse_fail_fast_evidence
      started = monotonic
      guess_tests
      @run_evidence = Baseline::RunEvidence.new(config: config, extra_files: @evidence_files) if @capture_evidence
      ignore_list = @replay ? IgnoreList.new([]) : IgnoreList.load(config.path("ignore_file"))
      warn_custom_map
      boot = Boot.new(config, hooks)
      begin
        integration, files, load_lines = boot_target(boot)
        @rails = boot.rails
        subjects, scope = select_subjects(files)
        results = subjects.empty? ? [] : mutate(subjects, files, integration, scope, ignore_list, load_lines:)
        @diagnostics.warnings.concat(ignore_list.apply(results))
        build_report(results, subjects, scope, started)
      ensure
        # The run boundary for the per-worker databases: cleanup runs however
        # the call ends - a boot that raised partway through, a baseline or
        # coverage failure, no subjects, no runnable work - so a host that
        # embeds Engine and calls it repeatedly never holds copies or
        # snapshots until process exit. cleanup_workers is idempotent; the
        # Rails profile's at_exit handler stays as the fallback for an
        # abrupt process exit.
        safely_cleanup_workers(boot.rails)
      end
    end

    def warn_custom_map
      @diagnostics.warnings.concat(custom_map_warnings(load_custom_map))
    end

    # Stale entries and duplicate literals never fail a run; they warn so the
    # map does not rot silently. doctor fails on stale keys.
    def load_custom_map
      @replay ? CustomMap.new([]) : CustomMap.load(config.path("custom_map"), root: config.root)
    end

    def custom_map_warnings(map)
      path = config.path("custom_map")
      warnings = map.stale_keys.map { |key| "stale custom map key #{key}: matches no file" }
      return warnings unless path && File.file?(path)

      warnings + map.duplicate_keys(path).map { |key| "duplicate custom map key #{key}: Ruby keeps the last" }
    end

    private

    # --guess-tests with --since: scope the run to the specs found next to
    # the changed files, as --test would, but only when each changed file
    # has one. Otherwise the whole suite runs, as without the flag.
    def guess_tests
      return unless config["guess_tests"]

      guess = TestGuess.new(config).call
      message =
        if guess.changed.zero?
          "--guess-tests: no changed source file to guess specs for, so the whole suite runs"
        elsif guess.unmatched.any?
          "--guess-tests: no spec found for #{guess.unmatched.join(', ')}, so the whole suite runs " \
            "(name specs after their source files or pass --test)"
        else
          # The guesses now stand as explicit tests, like --test.
          @config = Config.new(config.to_h.merge("tests" => guess.specs, "guess_tests" => false), root: config.root)
          @guessed_tests = guess.specs
          "--guess-tests: running only #{guess.specs.join(', ')}. A spec that reaches a changed file only " \
            "through another file does not run, so a mutant only it would kill can survive, and a line " \
            "no guessed spec executes is reported as NoCoverage"
        end
      @diagnostics.warn(message)
      @diagnostics.inform(message)
    end

    # The run's immutable report, built once the last result is in.
    def build_report(results, subjects, scope, started)
      Report.new(results: results, subjects: subjects, wall_time: monotonic - started, root: @root,
                 invalid_mutations: @diagnostics.invalid_mutations, warnings: @diagnostics.warnings,
                 review: !scope.nil?, seed: config["seed"], skipped_subjects: @skipped_subjects,
                 diff_scope: scope, generation_events: @diagnostics.generation_events,
                 omissions: @diagnostics.omissions, run_evidence: complete_evidence(results, subjects),
                 hazard_suppressions: @diagnostics.hazard_suppressions, early_stop: @early_stop,
                 matrix: config["matrix"], inline_suppressions: @diagnostics.inline_suppressions)
    end

    def complete_evidence(results, subjects)
      return nil unless @run_evidence

      @run_evidence.plan(subjects, subjects.map { [] }) unless @evidence_planned
      @run_evidence.finish(results: results, stable_suite: @stable_suite, skipped_subjects: @skipped_subjects,
                           generation_events: @diagnostics.generation_events, omissions: @diagnostics.omissions,
                           discovery_failures: @diagnostics.discovery_failures,
                           inline_suppressions: @diagnostics.inline_suppressions)
    end

    # The subjects to mutate and, in diff mode, the scope of changed lines.
    def select_subjects(files)
      config.unmatched_patterns.each { |pattern| @diagnostics.warn("#{pattern} matches no file") }
      selection = SubjectSelection.new(config, @diagnostics)
      subjects = selection.select(files)
      scope = selection.changed_lines && DiffScope.new(selection.changed_lines)
      return replay_subject(subjects, scope) if @replay

      [subjects, scope]
    end

    def mutate(subjects, files, integration, scope, ignore_list, load_lines: {})
      warn_about_unscoped_suite(integration)
      check_baseline(integration)
      map = CoverageStore.new(config: config, integration: integration, hooks: hooks, load_lines:,
                              supervisor: supervisor(memory_factor: 4), diagnostics: @diagnostics).fetch(files)
      inform_about_run(subjects, map)
      cache = result_cache
      scheduler = scheduler_for(map, integration, cache)
      lists = candidate_lists(subjects, scope, map)
      work = subjects.zip(lists).reject { |_, list| list.empty? }
      return [] if work.empty?

      runnable_subjects, runnable_lists = work.transpose
      @rails&.prepare_workers(config["jobs"])
      # The execution phase forks next: the worker batch, or one child per
      # mutant when serial. Pack the heap now that the map and candidates
      # are retained, to reduce later copying of shared pages.
      Execution::ForkReadiness.prepare_heap
      results = run_candidates(runnable_subjects, runnable_lists, scheduler, cache, ignore_list)
      cache&.save
      results
    end

    def run_candidates(subjects, lists, scheduler, cache, ignore_list)
      @diagnostics.start_progress(lists.sum(&:size))
      distribution = Distribution.new(jobs: config["jobs"], scheduler: scheduler, diagnostics: @diagnostics,
                                      cache: cache, on_start: method(:start_worker),
                                      after_subject: canary_check, stop_after: fail_fast_check(ignore_list))
      distribution.run(subjects, lists).tap { record_early_stop(distribution.unreached) }
    ensure
      @diagnostics.finish_progress
    end

    # Baseline evidence certifies a whole selection; a run that may stop early
    # cannot.
    def refuse_fail_fast_evidence
      return unless @capture_evidence && config["fail_fast"]

      raise ConfigError, "fail_fast cannot be used with baseline evidence: it certifies the whole selection"
    end

    # Subjects that were selected but never ran, with candidates, are part of
    # the report: the verdict covers less than the selection.
    def record_early_stop(unreached)
      return if unreached.empty?

      @early_stop = EarlyStop.new(reason: "fail_fast", unreached: unreached.map(&:id))
    end

    # --fail-fast: stop after the first subject that has a survivor the
    # ignore list does not accept. Granularity is one subject.
    def fail_fast_check(ignore_list)
      return nil unless config["fail_fast"]

      lambda do |results|
        survivor = results.any? { |result| result.survived? && !ignore_list.accepts?(result) }
        @diagnostics.inform("--fail-fast: stopping after the first subject with a survivor") if survivor
        survivor
      end
    end

    def inform_about_run(subjects, map)
      @diagnostics.inform("#{subjects.size} subjects, #{map.tests.size} tests in coverage map")
      warn_about_threads
    end

    # A --since run without --test runs the loaded suite twice for the
    # baselines; a cold coverage cache adds one more pass. Say so
    # before those hours pass, with the way to scope it.
    def warn_about_unscoped_suite(integration)
      return unless config["since"] && config["tests"].empty?

      message = "running the loaded suite unscoped: two baseline passes; coverage may add a pass " \
                "(#{integration.test_files.size} spec files). " \
                "Pass --test to run only the specs you name: faster, but a mutant of a changed method is then killed " \
                "only by those specs, so specs elsewhere that call this code are not run. " \
                "--guess-tests does the same with the specs named after the changed files, " \
                "a guess that can miss specs elsewhere."
      @diagnostics.warn(message)
      @diagnostics.inform(message)
    end

    def check_baseline(integration)
      BaselineGuard.new(config: config, integration: integration, hooks: hooks,
                        supervisor: supervisor(memory_factor: 4), diagnostics: @diagnostics).call
      @stable_suite = true
    end

    def scheduler_for(map, integration, cache)
      reevaluator = Execution::Reevaluator.new(config["reeval"], whole_file: config["whole_file"])
      runner = Execution::Runner.new(integration: integration, reevaluator: reevaluator, hooks: hooks,
                                     supervisor: supervisor, log_dir: fresh_log_dir, seed: config["seed"],
                                     sandbox: sandbox_hook)
      Scheduler.new(config: config, runner: runner, map: map, reevaluator: reevaluator, diagnostics: @diagnostics,
                    cache: cache)
    end

    # The sandbox hook for each mutant child (#152); the policy and its
    # one-time note live in Engine::SandboxPolicy.
    def sandbox_hook
      @sandbox_policy ||= SandboxPolicy.new(config: config, root: @root, diagnostics: @diagnostics)
      @sandbox_policy.hook
    end

    def result_cache
      return nil if @replay
      return nil unless config["incremental"]

      inputs = JSON.generate(VERDICT_INPUTS.to_h { |key| [key, config[key]] })
      ResultCache.new(path: File.join(config.path("cache_dir"), "results.json"), root: @root, inputs: inputs,
                      suite_digest: SuiteFiles.new(config).digest)
    end

    # A cleanup failure must never mask the run's own outcome - not even
    # one cleanup_workers did not anticipate.
    def safely_cleanup_workers(rails)
      rails&.cleanup_workers
    rescue StandardError => e
      @diagnostics.warn(e.message)
    end

    # In each worker: its own database, then the user's worker_start hooks.
    def start_worker(number)
      @rails&.start_worker(number)
      hooks.run(:worker_start, number)
    end

    # Each subject's candidates, narrowed to changed lines in diff mode.
    # The hazard guard is off only when the user explicitly asks for the
    # dangerous mutants (issue #102); the canary then still watches the tree.
    def hazard_guard
      return nil if config["allow_hazardous"]

      MutationSource::HazardGuard.new(config["hazard"])
    end

    # Checks the tree after each subject's mutants; a vanished file means a
    # mutant deleted it, so abort with the most recent mutant's digest.
    def canary_check
      canary = Canary.new(@root, cache_dir: config["cache_dir"])
      lambda do |subject, results|
        last = results.reject(&:reused?).last || results.last
        digest = last&.mutation&.digest(subject_start: subject.start_byte,
                                        original_source: subject.file_source)
        canary.check!(subject: subject, digest: digest)
      end
    end

    def candidate_lists(subjects, scope, map)
      return [@replay_candidate] if @replay

      candidates = Candidates.new(Candidates.build_sources(config), @diagnostics, hazard_guard: hazard_guard)
      selection = CandidateSelection.new(candidates: candidates, map: map,
                                         limit: config["max_mutants_per_method"], diagnostics: @diagnostics)
      subjects.map { |subject| selection.for(subject, scope: scope) }.tap do
        @skipped_subjects = selection.skipped_subjects
        if @run_evidence
          @run_evidence.plan(subjects, subjects.map { |subject| selection.selected.fetch(subject) })
          @evidence_planned = true
        end
      end
    end

    def replay_subject(subjects, scope)
      candidates = Candidates.new(Candidates.build_sources(config), @diagnostics, hazard_guard: hazard_guard)
      subject, candidate = @replay.select(subjects, candidates, scope: scope)
      @replay_candidate = [candidate]
      [[subject], nil]
    end

    def supervisor(memory_factor: 1)
      limits = Execution::Supervisor::Limits.new(max_memory_mb: config["max_memory_mb"] * memory_factor,
                                                 max_processes: config["max_processes"])
      Execution::Supervisor.new(limits: limits)
    end

    # The last run's child logs (only those of errors are kept).
    def fresh_log_dir
      File.join(config.path("cache_dir"), "logs").tap do |dir|
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
      end
    end

    # Threads do not survive fork, so name them: with the name the owner
    # gave the thread, else the first frame of its backtrace, so the user
    # can tell whether they matter (a connection pool reaper, Sidekiq, an
    # SDK's background flusher).
    def warn_about_threads
      others = Thread.list - [Thread.current]
      return if others.empty?

      names = others.map { |thread| thread.name || thread.backtrace&.first || "unknown" }
      list = names.join(", ")
      @diagnostics.warn("#{others.size} other thread(s) alive at fork time; they do not run in children: #{list}")
    end

    # The lines that ran while the app and spec files loaded: the executable
    # counts from its first line, so this snapshot holds the whole boot.
    # Read here, in the parent: a forked child does not inherit Coverage
    # counters. They become the map's load lines, which tell ran-at-load
    # mutants apart from uncovered ones.
    def capture_load_lines(files)
      return {} unless Coverage.state == :suspended

      wanted = files.to_set { |file| Selection::CoverageMap.canonical(file) }
      Coverage.result(stop: false, clear: false).each_with_object({}) do |(path, data), hits|
        file = Selection::CoverageMap.canonical(path)
        next unless wanted.include?(file)

        lines = data[:lines].each_with_index.filter_map { |count, index| index + 1 if count&.positive? }
        lines -= uncalled_shared_lines(data)
        hits[file] = lines unless lines.empty?
      end
    end

    # A one-line or endless definition executes its def line even when its
    # body is never called. If any sibling on that physical line is uncalled,
    # discard its ambiguous line evidence rather than crediting every body.
    def uncalled_shared_lines(data)
      shared = data.fetch(:methods, {}).select { |(_owner, _name, first, _column, last, *), _| first == last }
      calls = shared.group_by { |(_owner, _name, first, *), _count| first }
      calls.filter_map { |line, entries| line if entries.any? { |_key, count| count.zero? } }
    end

    # Loads the target and stops coverage, returning what the rest of the
    # run needs from that boot.
    def boot_target(boot)
      integration = boot.load_target
      files = config.included_files
      [integration, files, suspend_coverage(files)]
    end

    def suspend_coverage(files)
      Coverage.suspend if Coverage.state == :running
      capture_load_lines(files)
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end

require_relative "engine/diagnostics"
require_relative "engine/boot"
require_relative "engine/subject_selection"
require_relative "engine/unchanged_syntax"
require_relative "engine/suite_files"
require_relative "engine/test_guess"
require_relative "engine/sandbox_policy"
require_relative "engine/coverage_store"
require_relative "engine/baseline_guard"
require_relative "engine/bytecode_equivalence"
require_relative "engine/candidates"
require_relative "engine/candidate_selection"
require_relative "engine/diff_scope"
require_relative "engine/result_cache"
require_relative "engine/verdict_check"
require_relative "engine/scheduler"
require_relative "engine/canary"
require_relative "engine/distribution"

require_relative "engine/run_fingerprint"
