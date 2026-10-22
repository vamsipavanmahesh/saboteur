# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "replay"
require_relative "text"
require_relative "mutation_source/hazard_guard"
require_relative "baseline/run_evidence"
require_relative "engine/early_stop_recording"
require_relative "engine/gated_run"
require_relative "engine/load_coverage"
require_relative "engine/out_of_scope_guard"
require_relative "engine/run_budget"
require_relative "engine/selection_announcement"
require_relative "engine/survivor_confirmation"
require_relative "engine/thread_warnings"

require_relative "engine/pipelines"
require_relative "engine/shard"
require_relative "engine/suite_partition"

module Saboteur
  # A single-use instance runs one pipeline: boot the target, select subjects, fetch the
  # coverage map, then schedule each subject's mutants. The parts live in
  # engine/; this class only wires them together.
  class Engine
    include EarlyStopRecording
    include OutOfScopeGuard
    include RunBudget
    include GatedRun
    include SelectionAnnouncement

    # Confirmation only guards a partial coverage map, so it is silent unless
    # the user opted into partial_coverage = use (#1228).
    CONFIRMATION_SKIPPED = "survivor confirmation skipped: partial_coverage = use applies only to a cached " \
                           "whole-suite run (no --test, one coverage part)"

    # Everything besides sources and tests that can change a verdict.
    VERDICT_INPUTS = %w[integration require rspec_args rails reeval sources operators exclude_operators arid
                        timeout_factor timeout_min
                        max_memory_mb max_processes seed tests whole_file].freeze

    attr_reader :config, :hooks
    # The specs inference narrowed the run to, or nil when it did not.
    attr_reader :guessed_tests

    def initialize(config, err: $stderr, digest: nil, capture_evidence: false, evidence_files: [], verbose: false,
                   palette: nil, quiet_start: true, quiet: false)
      @config = config
      @hooks = Hooks.new
      @diagnostics = Diagnostics.new(err, verbose: verbose, palette: palette, quiet_start: quiet_start,
                                          quiet: quiet)
      @completed_baseline_passes = 0
      @baseline_elapsed = 0.0
      @root = File.realpath(config.root)
      @skipped_subjects = {}
      @replay = Replay.new(digest: digest) if digest
      if capture_evidence && (digest || config["since"] || config["incremental"] || config["resume"] || config["shard"])
        raise ConfigError,
              "baseline evidence requires fresh whole-scope execution: no since, replay, shard, resume or incremental"
      end

      @capture_evidence = capture_evidence
      @evidence_files = evidence_files
      @stable_suite = false
    end

    def call
      preflight!
      ensure_artifacts_self_ignored
      started = monotonic
      start_budget_clock(started)
      # Capture evidence inputs before inference narrows the test list: the
      # fingerprint must match what the baseline workflow recomputes from the
      # declared config, and the inferred specs are pinned by the hashed
      # source files anyway.
      @run_evidence = Baseline::RunEvidence.new(config: config, extra_files: @evidence_files) if @capture_evidence
      select_tests unless external_command?
      announce_operators
      ignore_list = @replay ? IgnoreList.new([]) : IgnoreList.load(config.path("ignore_file"))
      warn_custom_map
      run_pipeline(ignore_list, started)
    end

    include Pipelines

    def preflight!
      Boot.refuse_recursion!
      refuse_fail_fast_evidence
      verify_resume_directory
    end

    # An unusable --resume directory fails before the expensive phases (#471).
    def verify_resume_directory
      return if @replay || !config["resume"]

      ResumeManifest.new(directory: config.path("resume"), identity: Digest::SHA256.hexdigest(verdict_inputs)).verify!
    rescue ResumeManifest::Mismatch => e
      raise ConfigError, e.message
    end

    def warn_custom_map = @diagnostics.add_warnings(custom_map_warnings(load_custom_map))

    # Stale entries and duplicate literals never fail a run; they warn so the
    # map does not rot silently. doctor fails on stale keys.
    def test_guess = TestGuess.new(config, diagnostics: @diagnostics, custom_map: load_custom_map)

    def load_custom_map
      @load_custom_map ||= @replay ? CustomMap.new([]) : CustomMap.load(config.path("custom_map"), root: config.root)
    end

    def custom_map_warnings(map)
      path = config.path("custom_map")
      warnings = map.stale_keys.map { |key| "stale custom map key #{key}: matches no file" }
      return warnings unless path && File.file?(path)

      warnings + map.duplicate_keys(path).map { |key| "duplicate custom map key #{key}: Ruby keeps the last" }
    end

    # The map this run selected tests from: survivor presentation compares
    # it against the cached whole-suite map (review C1).
    def run_coverage_map
      @coverage_store&.fetched_map
    end

    # The cached whole-suite map on this tree, for survivor presentation
    # in scoped runs; nil when caching is off or no full build ran (review C1).
    def whole_suite_coverage_map
      @coverage_store&.whole_suite_map
    end

    # True when this run did not build a whole-suite map: a diff, named
    # subjects, an explicit --test or inferred specs (#1286).
    def scoped_selection?
      !whole_suite_run?
    end

    # False when caching is off, where no coverage build can ever leave a
    # whole-suite map to consult, so advising one would be wrong (review C1).
    def whole_suite_map_lookup?
      config["cache"] ? true : false
    end

    private

    # Inferred test selection, the default since 0.7.0: scope the run to the
    # specs found next to the mutated files, as --test would. With --since
    # only files whose changed lines carry a mutation subject need a spec;
    # without it every included file with a subject does. A file that needs
    # a spec and has none stops the run before boot, rather than silently
    # narrowing the source scope or widening the test run to the whole
    # suite. --all and c.test_selection = :all keep the whole suite.
    # A replay keeps its recorded tests, and a --subject run infers only
    # from the named subjects' files, so one unrelated spec-less file can
    # never block a one-method run.
    def select_tests
      return if !config["tests"].empty? || @replay || config["all"] || config["test_selection"] == "all"

      subjects = config["subjects"]
      return select_subject_tests(subjects) if subjects.any?

      guess = test_guess.call
      @diagnostics.inform(guess.excluded_message) if guess.excluded.any? && guess.specs.any?
      report_unmapped(guess)
      refuse_out_of_scope_changes(guess)

      announce_selection(guess)
    end

    # A --subject run infers only from the files holding the named subjects:
    # an unrelated spec-less file must not block a one-method run, and a
    # subject file without a conventional spec stops the run before boot.
    # With --since only named subjects inside the diff scope count: an
    # unchanged, comment-only or otherwise pruned subject needs no spec.
    def select_subject_tests(patterns)
      files = SubjectSelection.files_matching(@root, config.included_files, patterns, config)
      guess = test_guess.call_for(files, patterns)
      # No file in scope: the subjects are unknown (named later, in
      # selection) or --since left every named subject outside the diff, so
      # the run has nothing to mutate and needs no inferred spec.
      return if guess.changed.zero?

      inform_skipped_specs(guess)
      raise ConfigError, guess.unmatched_message(verbose: @diagnostics.verbose) if guess.unmatched.any?

      @diagnostics.inform(guess.excluded_message) if guess.excluded.any?
      # Every file in scope intentionally untested: mutate nothing. An
      # empty guess must never read as "run the whole suite" (#369).
      return if guess.specs.empty?

      @diagnostics.announce(scope_to_guesses(guess))
    end

    # The run's immutable report, built once the last result is in.
    def announce_operators = @diagnostics.detail("Operators: #{config.operator_policy['effective'].join(', ')}")

    def build_report(results, subjects, scope, started)
      Report.new(results: results, subjects: subjects, wall_time: monotonic - started, root: @root,
                 invalid_mutations: @diagnostics.invalid_mutations, warnings: @diagnostics.warnings,
                 live_announced: @diagnostics.live_announced,
                 review: !scope.nil?, seed: config["seed"], skipped_subjects: @skipped_subjects,
                 diff_scope: scope, generation_events: @diagnostics.generation_events,
                 omissions: @diagnostics.omissions, run_evidence: complete_evidence(results, subjects),
                 hazard_suppressions: @diagnostics.hazard_suppressions, early_stop: @early_stop,
                 matrix: config["matrix"], inline_suppressions: @diagnostics.inline_suppressions,
                 operator_policy: config.operator_policy, discovery_failures: @diagnostics.discovery_failures,
                 test_command: config["test_command"], reuse_label: reuse_label, since: config["since"],
                 shard: @shard, memory: @memory_report, referenced: @guessed_referenced || {},
                 phase_timings: @phase_timings)
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
    def select_subjects(files, test_files: nil)
      config.unmatched_patterns.each { |pattern| @diagnostics.warn("#{pattern} matches no file") }
      selection = SubjectSelection.new(config, @diagnostics,
                                       test_files: test_files, custom_map: load_custom_map)
      subjects = selection.select(files)
      scope = selection.behavior_lines && DiffScope.new(selection.behavior_lines)
      return replay_subject(subjects, scope) if @replay

      [subjects, scope]
    end

    def mutate(subjects, files, integration, scope, ignore_list, load_lines: {}, load_methods: {})
      store = coverage_store(integration, load_lines, load_methods)
      map_reusable = store.reusable?(files)
      full_passes = config["baseline_passes"] + (map_reusable ? 0 : 1)
      baseline_preflight(store, integration, files, full_passes)
      refuse_unaffordable_coverage_build(store, files)
      return [] if abandon_for_budget?(subjects)

      map, map_seconds = timed_map_fetch(store, files)
      inform_about_run(subjects, map)
      cache = result_cache(map, files)
      scheduler = scheduler_for(map, integration, cache)
      lists = candidate_lists(subjects, scope, map)
      runnable_subjects, runnable_lists = subjects.zip(lists).reject { |_, list| list.empty? }.transpose
      return [] if runnable_subjects.nil?

      @rails&.prepare_workers(config["jobs"])
      # The execution phase forks next: the worker batch, or one child per
      # mutant when serial. Pack the heap now that the map and candidates
      # are retained, to reduce later copying of shared pages.
      Execution::ForkReadiness.prepare_heap
      results = run_and_confirm_timed(runnable_subjects, runnable_lists, scheduler, cache, ignore_list,
                                      map_cached: map_reusable, map_seconds:)
      cache&.save
      results
    rescue BudgetPhaseTimeout => e
      budget_phase_stop(e, subjects)
    end

    # The map phase's monotonic split, for the speed footer.
    def timed_map_fetch(store, files)
      started = monotonic
      [store.fetch(files), monotonic - started]
    end

    # Baseline phase: announce, then verify the unchanged tree passes.
    def baseline_preflight(store, integration, files, full_passes)
      warn_unscoped(integration, full_passes)
      announce_quiet_start(store, files)
      check_baseline(integration, full_passes)
    end

    # The mutant phase plus the run's three disjoint timing intervals
    # (baseline inside check_baseline, map build, mutants) and the worker
    # count, recorded for the terminal's speed footer.
    def run_and_confirm_timed(subjects, lists, scheduler, cache, ignore_list, map_cached:, map_seconds:)
      started = monotonic
      results = run_and_confirm(subjects, lists, scheduler, cache, ignore_list)
      # @baseline_elapsed is a Float from initialize on, so no fallback is needed.
      @phase_timings = PhaseTimings.new(baseline_seconds: @baseline_elapsed,
                                        map_seconds:, map_cached:,
                                        mutants_seconds: monotonic - started,
                                        jobs: config["jobs"])
      results
    end

    # The candidate run plus the opt-in post-run confirmation pass (#1063):
    # confirmation runs after the last result, before the verdict cache is
    # written, so a confirmed kill overwrites the survivor verdict the run
    # cached (#1079). BudgetPhaseTimeout is not raised from the pass:
    # post-run its rescue would discard every result, so a spent budget
    # marks the remaining survivors unconfirmed instead.
    def run_and_confirm(subjects, lists, scheduler, cache, ignore_list)
      confirm_survivors(run_candidates(subjects, lists, scheduler, cache, ignore_list), scheduler, cache, ignore_list)
    end

    def confirm_survivors(results, scheduler, cache, ignore_list)
      unless CoveragePartial.use?(config, config["coverage_parts"])
        live = results.any? { |result| result.survived? && !ignore_list.accepts?(result) }
        @diagnostics.inform(CONFIRMATION_SKIPPED) if live && config["partial_coverage"] == "use"
        return results
      end

      SurvivorConfirmation.new(config: config, map: scheduler.map, scheduler: scheduler, diagnostics: @diagnostics,
                               budget_exceeded: method(:budget_exceeded?), cache: cache)
                          .call(results, ignore_list: ignore_list, early_stop: @early_stop)
    end

    def run_candidates(subjects, lists, scheduler, cache, ignore_list)
      @diagnostics.start_progress(lists.sum(&:size))
      distribution = Distribution.new(jobs: external_command? ? 1 : config["jobs"], scheduler: scheduler,
                                      diagnostics: @diagnostics,
                                      cache: cache, on_start: method(:start_worker),
                                      after_subject: after_subject_hook, stop_after: stop_checks(ignore_list),
                                      halt_check: config["max_duration"] ? method(:budget_exceeded?) : nil)
      distribution.run(subjects, lists).tap do
        record_early_stop(distribution, planned_mutants: lists.sum(&:size))
        @memory_report = distribution.memory_report
      end
    ensure
      @diagnostics.finish_progress
    end

    # Baseline evidence certifies a whole selection; a run that may stop early
    # cannot.
    def refuse_fail_fast_evidence
      return unless @capture_evidence && config["fail_fast"]

      raise ConfigError, "fail_fast cannot be used with baseline evidence: it certifies the whole selection"
    end

    # --fail-fast: stop after the first subject that has a survivor the
    # ignore list does not accept. Granularity is one subject.
    # --fail-fast and --max-duration both stop before the next subject; the
    # distribution records whatever they leave unreached.
    def stop_checks(ignore_list)
      checks = [fail_fast_check(ignore_list), ->(_results) { budget_exceeded? }].compact
      ->(results) { checks.any? { |check| check.call(results) } }
    end

    def fail_fast_check(ignore_list)
      return nil unless config["fail_fast"]

      lambda do |results|
        survivor = results.any? { |result| result.survived? && !ignore_list.accepts?(result) }
        @diagnostics.inform("--fail-fast: stopping after the first subject with a survivor") if survivor
        survivor
      end
    end

    # The default view's first line: the run's identity, dim, before the
    # baseline's own chatter (demoted to --verbose) would start.
    def announce_quiet_start(store, files)
      @map_cached = store.reusable?(files)
      @diagnostics.quiet_start_header(scope: quiet_scope,
                                      seed: config["seed"], operators: config.operator_policy["effective"].size)
    end

    # Names what the run covers: the diff, the --subject filter, or the
    # whole project (P6) - a --subject run is not "whole project".
    def quiet_scope
      parts = []
      parts << "--since #{config['since']}" if config["since"]
      parts << "--subject #{config['subjects'].join(', ')}" if config["subjects"].any?
      parts.empty? ? "whole project" : parts.join(", ")
    end

    def inform_about_run(subjects, map)
      if @diagnostics.quiet_start && !@diagnostics.verbose
        @diagnostics.quiet_baseline(passes: @completed_baseline_passes, elapsed: @baseline_elapsed,
                                    tests: map.tests.size, cached: @map_cached)
        @diagnostics.quiet_inference(@quiet_spec_count)
      else
        @diagnostics.inform("#{Text.counted(subjects.size, 'subject')}, " \
                            "#{Text.counted(map.tests.size, 'test')} in coverage map")
      end
      ThreadWarnings.warn(@diagnostics, rails: config["rails"])
    end

    # This run's map is the whole-suite map only when nothing scoped it:
    # no --since, no subjects, and every spec file loaded (--all or
    # c.test_selection = :all). Inferred specs are a selection, never the
    # whole suite: a spec with no matching source file is not in the map
    # (#1286).
    def whole_suite_run?
      config["since"].nil? && config["subjects"].empty? &&
        config["tests"].empty? && @guessed_tests.nil?
    end

    def coverage_store(integration, load_lines, load_methods = {})
      @coverage_store ||=
        CoverageStore.new(config: config, integration: integration, hooks: hooks, load_lines:, load_methods:,
                          whole_suite_run: whole_suite_run?,
                          supervisor: supervisor(memory_factor: 4), diagnostics: @diagnostics,
                          timeout_cap: method(:budget_capped_timeout),
                          parts: config["coverage_parts"])
    end

    def check_baseline(integration, full_passes)
      guard = BaselineGuard.new(config: config, integration: integration, hooks: hooks,
                                supervisor: supervisor(memory_factor: 4), diagnostics: @diagnostics,
                                full_passes: full_passes, timeout_cap: method(:budget_capped_timeout),
                                between_passes: config["max_duration"] ? method(:budget_exceeded?) : nil,
                                run_started: @run_started)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      guard.call
      @baseline_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      # Stability is the order comparison between completed checks: the cold
      # coverage build is not a baseline pass, and a budget break shortens
      # the loop, so certify only what actually ran.
      @stable_suite = (@completed_baseline_passes = guard.completed_passes) >= 2
    end

    # A --id replay targets one known mutant; the whole-suite cost summary
    # and its --test lecture do not apply.
    def warn_unscoped(integration, full_passes)
      UnscopedSuiteWarning.call(config:, diagnostics: @diagnostics, integration:, full_passes:) unless @replay
    end

    def scheduler_for(map, integration, cache)
      reevaluator = Execution::Reevaluator.new(config["reeval"], whole_file: config["whole_file"])
      runner = Execution::Runner.new(integration: integration, reevaluator: reevaluator, hooks: hooks,
                                     supervisor: supervisor, log_dir: fresh_log_dir, seed: config["seed"],
                                     sandbox: sandbox_hook, canary: canary)
      Scheduler.new(config: config, runner: runner, map: map, reevaluator: reevaluator, diagnostics: @diagnostics,
                    cache: cache, deadline: budget_deadline)
    end

    # The sandbox hook for each mutant child (#152); the policy and its
    # one-time note live in Engine::SandboxPolicy.
    def sandbox_hook
      @sandbox_policy ||= SandboxPolicy.new(config: config, root: @root, diagnostics: @diagnostics)
      @sandbox_policy.hook
    end

    # The dependency universe a cached verdict watches when coverage
    # cannot speak lives in Selection::CoverageMap (#344).
    def source_files(files, prefixes: Selection::CoverageMap.root_prefixes(config.root))
      Selection::CoverageMap.loaded_project_files(files, prefixes: prefixes)
    end

    def result_cache(map = nil, files = [])
      return nil if @replay
      return nil unless config["incremental"] || config["resume"]

      directory = config.path("resume") || config.path("cache_dir")
      ResultCache.new(path: File.join(directory, "results.json"), root: @root, inputs: verdict_inputs,
                      suite_digest: SuiteFiles.new(config).digest,
                      coverage: map, fallback_files: source_files(files))
    end

    # Which reuse mechanism is on, named as the flag the user typed, so the
    # terminal's reuse note never cites a flag that was not passed. A replay
    # runs one mutant fresh by design; it does not reuse, so it gets no label.
    def reuse_label
      return nil if @replay

      config["incremental"] ? "--incremental" : ("--resume" if config["resume"])
    end

    def verdict_inputs
      JSON.generate(VERDICT_INPUTS.to_h { |key| [key, config[key]] }.merge("operator_policy" => config.operator_policy))
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
    def hazard_guard = (MutationSource::HazardGuard.new(config["hazard"]) unless config["allow_hazardous"])

    # Checks the tree after each subject's mutants; a vanished file means a
    # mutant deleted it, so abort with the most recent mutant's digest.
    # Per finished subject: the canary, then the --verbose marks line that
    # makes a survivor attributable to its method mid-run (#262).
    def after_subject_hook
      canary = canary_check
      lambda do |subject, results|
        canary.call(subject, results)
        @diagnostics.subject_progress(subject, results)
      end
    end

    def canary_check
      lambda do |subject, results|
        last = results.reject(&:reused?).last || results.last
        digest = last&.mutation&.digest(subject_start: subject.start_byte,
                                        original_source: subject.file_source)
        canary.check!(subject: subject, digest: digest)
      end
    end

    # Shared with the runner so the hazard report wins over a log loss (#283).
    def canary = (@canary ||= Canary.new(@root, cache_dir: config["cache_dir"]))

    def candidate_lists(subjects, scope, map)
      return [@replay_candidate] if @replay

      candidates = Candidates.build(config, @diagnostics, hazard_guard: hazard_guard)
      selection = CandidateSelection.new(candidates: candidates, map: map,
                                         limit: config["max_mutants_per_method"], diagnostics: @diagnostics,
                                         root: @root)
      lists = subjects.map { |subject| selection.for(subject, scope: scope) }
      @shard = Engine::Shard.parse(config["shard"]) if config["shard"]
      lists = @shard.select(subjects, lists) if @shard
      lists.tap do
        @skipped_subjects = selection.skipped_subjects
        @unscoped_digests = selection.unscoped_digests
        if @run_evidence
          @run_evidence.plan(subjects, subjects.map { |subject| selection.selected.fetch(subject) })
          @evidence_planned = true
        end
      end
    end

    def replay_subject(subjects, scope)
      candidates = Candidates.build(config, @diagnostics, hazard_guard: hazard_guard)
      subject, candidate = @replay.select(subjects, candidates, scope: scope)
      @replay_candidate = [candidate]
      [[subject], nil]
    end

    def supervisor(memory_factor: 1)
      limits = Execution::Supervisor::Limits.new(max_memory_mb: config["max_memory_mb"] * memory_factor,
                                                 max_processes: config["max_processes"])
      Execution::Supervisor.new(limits: limits)
    end

    # Artifact dirs ignore themselves, the pattern git, vagrant and bundler
    # use: a run writes logs, coverage maps and reports under cache_dir, and
    # without the marker a `git add -A` commits them all (#426). An existing
    # .gitignore is the user's and stays. Best effort: a cache dir that
    # cannot be created or written belongs to the stages that need it, and
    # they refuse with their established wording (#512 CI fault injection).
    def ensure_artifacts_self_ignored
      dir = config.path("cache_dir")
      FileUtils.mkdir_p(dir)
      marker = File.join(dir, ".gitignore")
      File.write(marker, "*\n") unless File.exist?(marker)
    rescue SystemCallError
      nil
    end

    # The last run's child logs (only those of errors are kept).
    def fresh_log_dir
      File.join(config.path("cache_dir"), "logs").tap do |dir|
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
      end
    end

    # Loads the target and stops coverage, returning what the rest of the
    # run needs from that boot.
    def boot_target(boot)
      @diagnostics.detail("loading the application")
      integration = boot.load_target
      files = config.included_files
      load_lines, load_methods = suspend_coverage(files)
      [integration, files, load_lines, load_methods]
    end

    def suspend_coverage(files)
      (@coverage_guard = CoverageGuard.new(@diagnostics)).suspend
      # Coverage stops counting here, so the call tracer stops with it
      # instead of crediting the calls the engine itself makes afterwards.
      MethodCalls.booted&.pause
      LoadCoverage.capture(files)
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

require_relative "engine/coverage_guard"
require_relative "engine/diagnostics"
require_relative "engine/boot"
require_relative "engine/subject_selection"
require_relative "engine/unchanged_syntax"
require_relative "engine/suite_files"
require_relative "engine/reference_specs"
require_relative "engine/test_guess"
require_relative "engine/sandbox_policy"
require_relative "engine/coverage_inputs_snapshot"
require_relative "engine/partial_invalidation"
require_relative "engine/partial_merge"
require_relative "engine/shadow_comparison"
require_relative "engine/shadow_run"
require_relative "engine/coverage_shadow"
require_relative "engine/coverage_partial"
require_relative "engine/coverage_parts"
require_relative "engine/coverage_miss_note"
require_relative "engine/coverage_store"
require_relative "engine/baseline_guard"
require_relative "engine/unscoped_suite_warning"
require_relative "engine/bytecode_equivalence"
require_relative "engine/candidates"
require_relative "engine/candidate_selection"
require_relative "engine/diff_scope"
require_relative "engine/result_cache"
require_relative "engine/resume_manifest"
require_relative "engine/defined_order_prefix"
require_relative "engine/verdict_check"
require_relative "engine/scheduler"
require_relative "engine/canary"
require_relative "engine/distribution"

require_relative "engine/run_fingerprint"
