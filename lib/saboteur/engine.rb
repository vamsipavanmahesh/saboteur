# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # One run, as a pipeline: boot the target, select subjects, fetch the
  # coverage map, then schedule each subject's mutants. The parts live in
  # engine/; this class only wires them together.
  class Engine
    attr_reader :config, :hooks

    def initialize(config, err: $stderr)
      @config = config
      @hooks = Hooks.new
      @diagnostics = Diagnostics.new(err)
      @root = File.realpath(config.root)
    end

    def call
      Boot.refuse_recursion!
      started = monotonic
      ignore_list = IgnoreList.load(config.path("ignore_file"))
      integration = Boot.new(config, hooks).load_target
      files = config.included_files
      config.unmatched_patterns.each { |pattern| @diagnostics.warn("#{pattern} matches no file") }
      subjects = SubjectSelection.new(config, @diagnostics).select(files)
      results = subjects.empty? ? [] : mutate(subjects, files, integration)
      @diagnostics.warnings.concat(ignore_list.apply(results))
      Report.new(results: results, subjects: subjects, wall_time: monotonic - started, root: @root,
                 invalid_mutations: @diagnostics.invalid_mutations, warnings: @diagnostics.warnings)
    end

    private

    def mutate(subjects, files, integration)
      map = CoverageStore.new(config: config, integration: integration, hooks: hooks,
                              supervisor: supervisor(memory_factor: 4), diagnostics: @diagnostics).fetch(files)
      @diagnostics.inform("#{subjects.size} subjects, #{map.tests.size} tests in coverage map")
      warn_about_threads
      reevaluator = Execution::Reevaluator.new(config["reeval"])
      runner = Execution::Runner.new(integration: integration, reevaluator: reevaluator, hooks: hooks,
                                     supervisor: supervisor)
      scheduler = Scheduler.new(config: config, runner: runner, map: map, reevaluator: reevaluator,
                                diagnostics: @diagnostics)
      candidates = Candidates.new(Candidates.build_sources(config), @diagnostics)
      subjects.flat_map { |subject| scheduler.call(subject, candidates.for(subject)) }
    end

    def supervisor(memory_factor: 1)
      limits = Execution::Supervisor::Limits.new(max_memory_mb: config["max_memory_mb"] * memory_factor,
                                                 max_processes: config["max_processes"])
      Execution::Supervisor.new(limits: limits)
    end

    def warn_about_threads
      others = Thread.list.size - 1
      @diagnostics.warn("#{others} other thread(s) alive at fork time; they do not run in children") if
        others.positive?
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end

require_relative "engine/diagnostics"
require_relative "engine/boot"
require_relative "engine/subject_selection"
require_relative "engine/coverage_store"
require_relative "engine/candidates"
require_relative "engine/scheduler"
