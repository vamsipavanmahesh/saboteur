# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"

module Saboteur
  # One run, as a pipeline: boot the target, select subjects, fetch the
  # coverage map, then schedule each subject's mutants. The parts live in
  # engine/; this class only wires them together.
  class Engine
    # Everything besides sources and tests that can change a verdict.
    VERDICT_INPUTS = %w[integration require rspec_args rails reeval sources arid timeout_factor timeout_min
                        max_memory_mb max_processes seed].freeze

    attr_reader :config, :hooks

    def initialize(config, err: $stderr)
      @config = config
      @hooks = Hooks.new
      @diagnostics = Diagnostics.new(err)
      @root = File.realpath(config.root)
      @skipped_subjects = {}
    end

    def call
      Boot.refuse_recursion!
      started = monotonic
      ignore_list = IgnoreList.load(config.path("ignore_file"))
      boot = Boot.new(config, hooks)
      integration = boot.load_target
      @rails = boot.rails
      files = config.included_files
      subjects, scope = select_subjects(files)
      results = subjects.empty? ? [] : mutate(subjects, files, integration, scope)
      @diagnostics.warnings.concat(ignore_list.apply(results))
      Report.new(results: results, subjects: subjects, wall_time: monotonic - started, root: @root,
                 invalid_mutations: @diagnostics.invalid_mutations, warnings: @diagnostics.warnings,
                 review: !scope.nil?, seed: config["seed"], skipped_subjects: @skipped_subjects)
    end

    private

    # The subjects to mutate and, in diff mode, the scope of changed lines.
    def select_subjects(files)
      config.unmatched_patterns.each { |pattern| @diagnostics.warn("#{pattern} matches no file") }
      selection = SubjectSelection.new(config, @diagnostics)
      subjects = selection.select(files)
      [subjects, selection.changed_lines && DiffScope.new(selection.changed_lines)]
    end

    def mutate(subjects, files, integration, scope)
      map = CoverageStore.new(config: config, integration: integration, hooks: hooks,
                              supervisor: supervisor(memory_factor: 4), diagnostics: @diagnostics).fetch(files)
      @diagnostics.inform("#{subjects.size} subjects, #{map.tests.size} tests in coverage map")
      warn_about_threads
      cache = result_cache
      scheduler = scheduler_for(map, integration, cache)
      @rails&.prepare_workers(config["jobs"])
      lists = candidate_lists(subjects, scope, map)
      # The execution phase forks next: the worker batch, or one child per
      # mutant when serial. Pack the heap now that the map and candidates
      # are retained, to reduce later copying of shared pages.
      Execution::ForkReadiness.prepare_heap
      results = Distribution.new(jobs: config["jobs"], scheduler: scheduler, diagnostics: @diagnostics,
                                 cache: cache, on_start: method(:start_worker)).run(subjects, lists)
      cache&.save
      results
    end

    def scheduler_for(map, integration, cache)
      reevaluator = Execution::Reevaluator.new(config["reeval"])
      runner = Execution::Runner.new(integration: integration, reevaluator: reevaluator, hooks: hooks,
                                     supervisor: supervisor, log_dir: fresh_log_dir, seed: config["seed"])
      Scheduler.new(config: config, runner: runner, map: map, reevaluator: reevaluator, diagnostics: @diagnostics,
                    cache: cache)
    end

    def result_cache
      return nil unless config["incremental"]

      inputs = JSON.generate(VERDICT_INPUTS.to_h { |key| [key, config[key]] })
      ResultCache.new(path: File.join(config.path("cache_dir"), "results.json"), root: @root, inputs: inputs,
                      suite_digest: SuiteFiles.new(config).digest)
    end

    # In each worker: its own database, then the user's worker_start hooks.
    def start_worker(number)
      @rails&.start_worker(number)
      hooks.run(:worker_start, number)
    end

    # Each subject's candidates, narrowed to changed lines in diff mode.
    def candidate_lists(subjects, scope, map)
      candidates = Candidates.new(Candidates.build_sources(config), @diagnostics)
      selection = CandidateSelection.new(candidates: candidates, map: map,
                                         limit: config["max_mutants_per_method"], diagnostics: @diagnostics)
      subjects.map { |subject| selection.for(subject, scope: scope) }.tap do
        @skipped_subjects = selection.skipped_subjects
      end
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
require_relative "engine/suite_files"
require_relative "engine/coverage_store"
require_relative "engine/candidates"
require_relative "engine/candidate_selection"
require_relative "engine/diff_scope"
require_relative "engine/result_cache"
require_relative "engine/verdict_check"
require_relative "engine/scheduler"
require_relative "engine/distribution"
