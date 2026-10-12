# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "replay"

module Saboteur
  # A single-use instance runs one pipeline: boot the target, select subjects, fetch the
  # coverage map, then schedule each subject's mutants. The parts live in
  # engine/; this class only wires them together.
  class Engine
    # Everything besides sources and tests that can change a verdict.
    VERDICT_INPUTS = %w[integration require rspec_args rails reeval sources arid timeout_factor timeout_min
                        max_memory_mb max_processes seed tests].freeze

    attr_reader :config, :hooks

    def initialize(config, err: $stderr, digest: nil)
      @config = config
      @hooks = Hooks.new
      @diagnostics = Diagnostics.new(err)
      @root = File.realpath(config.root)
      @skipped_subjects = {}
      @replay = Replay.new(digest: digest) if digest
    end

    def call
      Boot.refuse_recursion!
      started = monotonic
      ignore_list = @replay ? IgnoreList.new([]) : IgnoreList.load(config.path("ignore_file"))
      @diagnostics.warnings.concat(custom_map_warnings(load_custom_map))
      boot = Boot.new(config, hooks)
      begin
        integration = boot.load_target
        @rails = boot.rails
        files = config.included_files
        subjects, scope = select_subjects(files)
        results = subjects.empty? ? [] : mutate(subjects, files, integration, scope)
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

    # Stale entries and duplicate literals never fail a run; they warn so the
    # map does not rot silently. doctor fails on stale keys.
    def load_custom_map
      @replay ? CustomMap.new([]) : CustomMap.load(config.path("custom_map"), root: config.root)
    end

    def custom_map_warnings(map)
      path = config.path("custom_map")
      warnings = map.stale_keys.map { |key| "stale custom map key #{key}: matches no file" }
      return warnings unless File.file?(path)

      warnings + map.duplicate_keys(path).map { |key| "duplicate custom map key #{key}: Ruby keeps the last" }
    end

    private

    # The run's immutable report, built once the last result is in.
    def build_report(results, subjects, scope, started)
      Report.new(results: results, subjects: subjects, wall_time: monotonic - started, root: @root,
                 invalid_mutations: @diagnostics.invalid_mutations, warnings: @diagnostics.warnings,
                 review: !scope.nil?, seed: config["seed"], skipped_subjects: @skipped_subjects,
                 diff_scope: scope)
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

    def mutate(subjects, files, integration, scope)
      warn_about_unscoped_suite(integration)
      check_baseline(integration)
      map = CoverageStore.new(config: config, integration: integration, hooks: hooks,
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
      results = Distribution.new(jobs: config["jobs"], scheduler: scheduler, diagnostics: @diagnostics,
                                 cache: cache, on_start: method(:start_worker)).run(runnable_subjects,
                                                                                    runnable_lists)
      cache&.save
      results
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
                "(#{integration.test_files.size} spec files). Pass --test to scope it."
      @diagnostics.warn(message)
      @diagnostics.inform(message)
    end

    def check_baseline(integration)
      BaselineGuard.new(config: config, integration: integration, hooks: hooks,
                        supervisor: supervisor(memory_factor: 4), diagnostics: @diagnostics).call
    end

    def scheduler_for(map, integration, cache)
      reevaluator = Execution::Reevaluator.new(config["reeval"])
      runner = Execution::Runner.new(integration: integration, reevaluator: reevaluator, hooks: hooks,
                                     supervisor: supervisor, log_dir: fresh_log_dir, seed: config["seed"])
      Scheduler.new(config: config, runner: runner, map: map, reevaluator: reevaluator, diagnostics: @diagnostics,
                    cache: cache)
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
    def candidate_lists(subjects, scope, map)
      return [@replay_candidate] if @replay

      candidates = Candidates.new(Candidates.build_sources(config), @diagnostics)
      selection = CandidateSelection.new(candidates: candidates, map: map,
                                         limit: config["max_mutants_per_method"], diagnostics: @diagnostics)
      subjects.map { |subject| selection.for(subject, scope: scope) }.tap do
        @skipped_subjects = selection.skipped_subjects
      end
    end

    def replay_subject(subjects, scope)
      candidates = Candidates.new(Candidates.build_sources(config), @diagnostics)
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
require_relative "engine/baseline_guard"
require_relative "engine/candidates"
require_relative "engine/candidate_selection"
require_relative "engine/diff_scope"
require_relative "engine/result_cache"
require_relative "engine/verdict_check"
require_relative "engine/scheduler"
require_relative "engine/distribution"

require_relative "engine/run_fingerprint"
