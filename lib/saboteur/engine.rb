# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "replay"
require_relative "mutation_source/hazard_guard"
require_relative "baseline/run_evidence"
require_relative "engine/early_stop_recording"
require_relative "engine/run_budget"
require_relative "engine/thread_warnings"

require_relative "engine/pipelines"

module Saboteur
  # A single-use instance runs one pipeline: boot the target, select subjects, fetch the
  # coverage map, then schedule each subject's mutants. The parts live in
  # engine/; this class only wires them together.
  class Engine
    include EarlyStopRecording
    include RunBudget

    # Everything besides sources and tests that can change a verdict.
    VERDICT_INPUTS = %w[integration require rspec_args rails reeval sources operators exclude_operators arid
                        timeout_factor timeout_min
                        max_memory_mb max_processes seed tests whole_file].freeze

    attr_reader :config, :hooks
    # The specs inference narrowed the run to, or nil when it did not.
    attr_reader :guessed_tests

    def initialize(config, err: $stderr, digest: nil, capture_evidence: false, evidence_files: [], verbose: false)
      @config = config
      @hooks = Hooks.new
      @diagnostics = Diagnostics.new(err, verbose: verbose)
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
      preflight!
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
    end

    def warn_custom_map = @diagnostics.warnings.concat(custom_map_warnings(load_custom_map))

    # Stale entries and duplicate literals never fail a run; they warn so the
    # map does not rot silently. doctor fails on stale keys.
    def test_guess = TestGuess.new(config, diagnostics: @diagnostics, custom_map: load_custom_map)

    # Name the files needing no spec, stop on spec-less files, then say
    # which specs the run scopes to (or why nothing mutates).
    def announce_guess(guess)
      @diagnostics.inform(guess.subjectless_message(since: config["since"])) if guess.subjectless.any?
      inform_skipped_specs(guess)
      raise ConfigError, guess.unmatched_message if guess.unmatched.any?

      refuse_out_of_scope_changes(guess)

      @diagnostics.announce(selection_message(guess))
    end

    def load_custom_map
      @load_custom_map ||= @replay ? CustomMap.new([]) : CustomMap.load(config.path("custom_map"), root: config.root)
    end

    def custom_map_warnings(map)
      path = config.path("custom_map")
      warnings = map.stale_keys.map { |key| "stale custom map key #{key}: matches no file" }
      return warnings unless path && File.file?(path)

      warnings + map.duplicate_keys(path).map { |key| "duplicate custom map key #{key}: Ruby keeps the last" }
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
      return unless config["tests"].empty?
      return if @replay || config["all"] || config["test_selection"] == "all"

      subjects = config["subjects"]
      return select_subject_tests(subjects) if subjects.any?

      guess = test_guess.call
      @diagnostics.inform(guess.excluded_message) if guess.excluded.any? && guess.specs.any?
      announce_guess(guess)
    end

    # Every changed source file sits outside the include scope (#483): the
    # whole-suite fallback would run the slowest possible suite against
    # zero subjects, so stop and name what the scope hid.
    def refuse_out_of_scope_changes(guess)
      return unless guess.changed.zero? && guess.out_of_scope.any?

      raise ConfigError, guess.out_of_scope_message
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
      raise ConfigError, guess.unmatched_message if guess.unmatched.any?

      @diagnostics.inform(guess.excluded_message) if guess.excluded.any?
      # Every file in scope intentionally untested: mutate nothing. An
      # empty guess must never read as "run the whole suite" (#369).
      return if guess.specs.empty?

      @diagnostics.announce(scope_to_guesses(guess))
    end

    # A spec file the diff touched that cannot run is named, also before a
    # stop on an unmatched file: --test, the way out, never reads the diff.
    def inform_skipped_specs(guess) = (@diagnostics.inform(guess.skipped_message) if guess.skipped_specs.any?)

    def selection_message(guess)
      if guess.changed.zero?
        target = config["since"] ? "no changed source file" : "no source file"
        "inferred specs: #{target} to infer a spec for, so the whole suite runs"
      elsif guess.specs.empty?
        guess.no_specs_message(since: config["since"])
      else
        scope_to_guesses(guess)
      end
    end

    # Stop before boot: name the spec-less files and the ways out. The
    # hinted spec paths are the conventional ones - they do not exist (that
    # is why the files are unmatched), so the message never prints them as
    # a runnable --test command, and it never reconstructs the source
    # scope: the user appends --test or --all to their own command. The
    # example is still shell-safe: the ref is user input, so it is quoted
    # and pinned to the flag with = (a ref like "-x" must not become a
    # switch).
    def scope_to_guesses(guess)
      # The guesses now stand as explicit tests, like --test. guess_tests is
      # dropped rather than set to false: an explicit false is the deprecated
      # opt-out and would warn.
      @config = config.with({ "tests" => guess.specs }, except: ["guess_tests"])
      @guessed_tests = guess.specs
      guess.scope_message(since: config["since"])
    end

    # The run's immutable report, built once the last result is in.
    def announce_operators = @diagnostics.inform("Operators: #{config.operator_policy['effective'].join(', ')}")

    def build_report(results, subjects, scope, started)
      Report.new(results: results, subjects: subjects, wall_time: monotonic - started, root: @root,
                 invalid_mutations: @diagnostics.invalid_mutations, warnings: @diagnostics.warnings,
                 review: !scope.nil?, seed: config["seed"], skipped_subjects: @skipped_subjects,
                 diff_scope: scope, generation_events: @diagnostics.generation_events,
                 omissions: @diagnostics.omissions, run_evidence: complete_evidence(results, subjects),
                 hazard_suppressions: @diagnostics.hazard_suppressions, early_stop: @early_stop,
                 matrix: config["matrix"], inline_suppressions: @diagnostics.inline_suppressions,
                 operator_policy: config.operator_policy, discovery_failures: @diagnostics.discovery_failures)
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

    def mutate(subjects, files, integration, scope, ignore_list, load_lines: {})
      store = coverage_store(integration, load_lines)
      full_passes = config["baseline_passes"] + (store.reusable?(files) ? 0 : 1)
      warn_unscoped(integration, full_passes)
      check_baseline(integration, full_passes)
      return [] if abandon_for_budget?(subjects)

      map = store.fetch(files)
      inform_about_run(subjects, map)
      cache = result_cache(map, files)
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
    rescue BudgetPhaseTimeout => e
      budget_phase_stop(e, subjects)
    end

    def run_candidates(subjects, lists, scheduler, cache, ignore_list)
      @diagnostics.start_progress(lists.sum(&:size))
      distribution = Distribution.new(jobs: external_command? ? 1 : config["jobs"], scheduler: scheduler,
                                      diagnostics: @diagnostics,
                                      cache: cache, on_start: method(:start_worker),
                                      after_subject: after_subject_hook, stop_after: stop_checks(ignore_list),
                                      halt_check: config["max_duration"] ? method(:budget_exceeded?) : nil)
      distribution.run(subjects, lists).tap { record_early_stop(distribution) }
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

    def inform_about_run(subjects, map)
      @diagnostics.inform("#{subjects.size} subjects, #{map.tests.size} tests in coverage map")
      ThreadWarnings.warn(@diagnostics)
    end

    def coverage_store(integration, load_lines)
      CoverageStore.new(config: config, integration: integration, hooks: hooks, load_lines:,
                        supervisor: supervisor(memory_factor: 4), diagnostics: @diagnostics,
                        timeout_cap: method(:budget_capped_timeout))
    end

    def check_baseline(integration, full_passes)
      guard = BaselineGuard.new(config: config, integration: integration, hooks: hooks,
                                supervisor: supervisor(memory_factor: 4), diagnostics: @diagnostics,
                                full_passes: full_passes, timeout_cap: method(:budget_capped_timeout),
                                between_passes: config["max_duration"] ? method(:budget_exceeded?) : nil)
      guard.call
      # Stability is the order comparison between completed checks: the cold
      # coverage build is not a baseline pass, and a budget break shortens
      # the loop, so certify only what actually ran.
      @stable_suite = guard.completed_passes >= 2
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
    # cannot speak: every project file the booted process loaded, plus
    # the run's own files (#344).
    def source_files(files, prefixes: Selection::CoverageMap.root_prefixes(config.root))
      $LOADED_FEATURES.filter_map do |file|
        path = Text.utf8_strict(Saboteur::Selection::CoverageMap.canonical(file))
        path if path.end_with?(".rb") && prefixes.any? { |prefix| path.start_with?(prefix) }
      end | files
    end

    def result_cache(map = nil, files = [])
      return nil if @replay
      return nil unless config["incremental"]

      inputs = JSON.generate(VERDICT_INPUTS.to_h { |key| [key, config[key]] }
                                            .merge("operator_policy" => config.operator_policy))
      ResultCache.new(path: File.join(config.path("cache_dir"), "results.json"), root: @root, inputs: inputs,
                      suite_digest: SuiteFiles.new(config).digest,
                      coverage: map, fallback_files: source_files(files))
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
                                         limit: config["max_mutants_per_method"], diagnostics: @diagnostics)
      subjects.map { |subject| selection.for(subject, scope: scope) }.tap do
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

    # The last run's child logs (only those of errors are kept).
    def fresh_log_dir
      File.join(config.path("cache_dir"), "logs").tap do |dir|
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
      end
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
      @diagnostics.inform("loading the application")
      integration = boot.load_target
      files = config.included_files
      [integration, files, suspend_coverage(files)]
    end

    def suspend_coverage(files)
      (@coverage_guard = CoverageGuard.new(@diagnostics)).suspend
      capture_load_lines(files)
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
require_relative "engine/test_guess"
require_relative "engine/sandbox_policy"
require_relative "engine/coverage_store"
require_relative "engine/baseline_guard"
require_relative "engine/unscoped_suite_warning"
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
