# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Runs one subject's candidates and returns their results. This is the
    # unit of work parallel workers will share out.
    #
    # Order of business: skip what cannot be run (refinements, not loaded,
    # shadowed, no covering test); coarse mutants; all eligible fine mutants;
    # then check every kill and timeout against the unchanged method
    # (VerdictCheck). Each mutant runs only the tests that executed its edit,
    # likeliest killers first, with a timeout from their recorded durations.
    class Scheduler
      BUDGET_RETRY_REASON = "the --max-duration budget stopped the defined-order retry"
      WHOLE_FILE_HINT = "; add it to c.whole_file to re-evaluate the whole file"

      # A subject to run, with what its mutants need. killers counts the
      # tests that killed earlier mutants of this subject; slowdown is how
      # much slower than recorded its tests ran in a child (see calibrate).
      # wrapper names a known def-time wrapper (Execution::Wrapper), so the
      # child re-evaluates it together with the def.
      Plan = Struct.new(:subject, :tests, :killers, :slowdown, :wrapper,
                        keyword_init: true)

      # Tests that killed more earlier mutants first; otherwise keep the order.
      def self.prioritize(tests, killers)
        tests.sort_by.with_index { |id, index| [-killers.fetch(id, 0), index] }
      end

      # verify_loaded: the shadowed-definition guard resolves each subject's
      # owner in this process. --test-command never boots the app here, so
      # external runs pass false; their neutral check covers a red tree.
      def initialize(config:, runner:, map:, reevaluator:, diagnostics:, cache: nil, deadline: nil,
                     verify_loaded: true)
        @config = config
        @deadline = deadline
        @runner = runner
        @map = map
        @reevaluator = reevaluator
        @diagnostics = diagnostics
        @cache = cache
        @verify_loaded = verify_loaded
      end

      def call(subject, candidates)
        return [] if candidates.empty?

        reason, wrapper = subject.skip_reason ? [subject.skip_reason, nil] : load_problem(subject)
        return skip_all(candidates, subject, reason) if reason
        if wrapper == :sorbet && !subject.sig_source
          return skip_all(candidates, subject,
                          "sorbet sig not found next to the def; cannot preserve runtime type checks")
        end

        tests = @map.tests_for(subject)
        return unloadable(candidates, subject) if tests.empty?
        return load_time_results(candidates, subject) if load_only?(subject)

        plan = Plan.new(subject:, tests:, killers: Hash.new(0), slowdown: 1.0, wrapper: wrapper)
        reused = all_reused(plan, candidates)
        return reused if reused

        results = run_candidates(candidates) do |mutation, text|
          reuse(plan, mutation, text) || execute(plan, mutation, text)
        end
        checked(plan, results, truncated: results.size < candidates.size)
      end

      # The per-mutant timeout: timeout_factor times what the tests took
      # while the map was built (times the subject's measured slowdown), and
      # never less than timeout_min.
      def timeout_for(tests, slowdown = 1.0)
        recorded = @map.recorded_runtime(tests)
        return @config["baseline_timeout"] unless recorded

        deadline(recorded * slowdown)
      end

      # Survivor confirmation (#1063) drives the runner and the coverage map
      # from outside after the run.
      attr_reader :runner, :map

      # The eval prefix a post-run confirmation run needs for this subject
      # (#1063): the same wrapper detection load_problem applies, reduced to
      # the sorbet sig prefix a survivor could have run with.
      def confirmation_prefix(subject)
        return nil unless @verify_loaded
        return nil if @reevaluator.whole_file?(subject)

        owner = @reevaluator.resolve_owner(subject)
        target = subject.singleton ? owner.singleton_class : owner
        method = own_method(target, subject.name)
        return nil unless method

        file, = method.source_location
        Execution::Wrapper.around(method, file) == :sorbet ? subject.sig_source : nil
      rescue Error
        nil
      end

      private

      # Verdicts that did not hold up are warned about once per subject;
      # only checked verdicts are stored for --incremental.
      # A spent budget admits no check for a subject that finished its
      # mutants: forking the unchanged run with no time left would turn
      # genuine kills into fabricated errors and cache them. Fresh kills
      # stand unverified instead - outside the score, never cached - and
      # the distribution marks the subject so the run reports
      # budget-partial.
      # A subject the budget stopped mid-list is different (#588): its
      # completed mutants were already measured, so their checks still
      # run, uncapped - the budget stops new mutation work, not the
      # confirmation of work already done. The overshoot stays bounded by
      # the subject's distinct killing sequences.
      def checked(plan, results, truncated: false)
        return results.map { |result| unverifiable(result) } if budget_spent? && !truncated

        @confirming_truncation = truncated
        subject = plan.subject
        check = VerdictCheck.new(run_unchanged: unchanged_runner(subject, plan),
                                 baseline_timeout: @config["baseline_timeout"])
        final = check.call(results).map { |result| retried_in_defined_order(plan, result) }
        # Unverified verdicts are never cached: a budget-cut check proves
        # nothing, and a stored copy would read as confirmed next run.
        final.reject { |result| result.reused? || result.status == :unverified }.each { |r| @cache&.record(r) }
        overturned = final.zip(results).count { |after, before| after.status == :error && !after.equal?(before) }
        if overturned.positive?
          @diagnostics.warn("#{subject.id}: #{overturned} verdict(s) failed with the method unchanged")
        end
        final
      ensure
        @confirming_truncation = false
      end

      # A kill rejected because its covering examples fail with the method
      # unchanged may only lack the setup examples the subset run skipped
      # (an order-dependent file, #557). Retry once with the file's examples
      # in defined order, through the last covering example. It stands only
      # if that whole run passes unchanged; the mutant's verdict is then the
      # mutant's run on the same examples. Otherwise the error stays.
      #
      # Cost bound: at most two extra forks per rejected kill, the unchanged
      # prefix run and one mutant run. Ordinarily both spend --max-duration
      # like every other fork: neither starts once the budget is spent, and
      # neither gets more than the time left. A retry the budget stops is
      # unverified, not an error or a kill. The exception is a truncated
      # subject (#588): its completed kills still retry, at the full
      # timeout. Keep this bound if the retry ever grows.
      def retried_in_defined_order(plan, result)
        return result unless result.rejected_kill? && !result.reused? && result.covered_by.any?

        tests = DefinedOrderPrefix.new(@map.tests).for(result.covered_by)
        return result unless tests

        unchanged = unchanged_runner(plan.subject, plan).call(tests, @config["baseline_timeout"])
        return result.as_unverified(unchanged.message || BUDGET_RETRY_REASON) if unchanged.status == :unverified
        return result unless unchanged.status == :survived

        rerun_in_prefix(plan, result, tests)
      end

      def rerun_in_prefix(plan, result, tests)
        return result.as_unverified(BUDGET_RETRY_REASON) if budget_spent? && !@confirming_truncation

        full = timeout_for(tests, plan.slowdown)
        capped = @confirming_truncation ? full : budget_capped(full)
        outcome = @runner.run(subject: plan.subject, text: result.mutated_source, test_ids: tests,
                              timeout: capped, mutation: result.mutation, eval_prefix: eval_prefix(plan))
        return result.as_unverified(BUDGET_RETRY_REASON) if outcome.status == :timeout && capped < full

        MutantResult.new(subject: plan.subject, mutation: result.mutation, status: outcome.status,
                         mutated_source: result.mutated_source, reason: outcome.message, runtime: outcome.runtime,
                         killed_by: outcome.failed_ids, covered_by: tests, kill_cause: outcome.kill_cause,
                         executed: outcome.executed_ids)
      end

      # Admission is per sequence, not just at checked() entry: a check
      # admitted with time left can hit its capped timeout mid-check, and a
      # later sequence can arrive after the budget is spent. Neither may
      # fork with no time left, and neither outcome is a rejected kill -
      # the check never got its answer (#296).
      def unchanged_runner(subject, plan)
        lambda do |tests, timeout|
          if budget_spent? && !@confirming_truncation
            Execution::Runner::Outcome.new(status: :unverified, runtime: 0.0,
                                           message: "the --max-duration budget is spent")
          else
            capped = @confirming_truncation ? timeout : budget_capped(timeout)
            outcome = @runner.run(subject: subject, text: subject.source, test_ids: tests, timeout: capped,
                                  eval_prefix: eval_prefix(plan))
            note_leftovers(subject, "verdict check", outcome)
            if outcome.status == :timeout && capped < timeout
              Execution::Runner::Outcome.new(status: :unverified, runtime: outcome.runtime,
                                             message: "the --max-duration budget cut the verdict check short")
            else
              outcome
            end
          end
        end
      end

      # When every verdict can be reused, nothing forks: not even the neutral
      # check. Returns the results, or nil at the first one that must run.
      def all_reused(plan, candidates)
        return nil unless @cache

        catch(:must_run) do
          run_candidates(candidates) { |mutation, text| reuse(plan, mutation, text) || throw(:must_run) }
        end
      end

      # The budget deadline is checked between mutants, so a spent
      # --max-duration stops inside a long subject too; completed results
      # are kept and the distribution marks what follows as unreached.
      def run_candidates(candidates, &run_one)
        coarse, fine = candidates.partition { |mutation, _| mutation.coarse }
        (coarse + fine).each_with_object([]) do |(mutation, text), results|
          break results if @deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline

          results << run_one.call(mutation, text)
        end
      end

      # A stored verdict that still holds, as a result; nil when it must run.
      def reuse(plan, mutation, text)
        return nil unless @cache

        tests = tests_for(plan, mutation)
        return uncoverable(plan, mutation, text) if tests.empty?

        hit = @cache.lookup(plan.subject, mutation, tests)
        return nil unless hit

        MutantResult.new(subject: plan.subject, mutation: mutation, status: hit[:status], mutated_source: text,
                         reason: hit[:reason], runtime: hit[:runtime], killed_by: hit[:killed_by],
                         covered_by: tests, kill_cause: hit[:kill_cause], reused: true)
      end

      def execute(plan, mutation, text)
        tests = tests_for(plan, mutation)
        return uncoverable(plan, mutation, text) if tests.empty?

        outcome = run_mutant(plan, mutation, text, tests)
        note_unreachable(plan, outcome) if outcome.status == :unreachable
        result = MutantResult.new(subject: plan.subject, mutation: mutation, status: outcome.status,
                                  mutated_source: text, reason: outcome.message, runtime: outcome.runtime,
                                  killed_by: outcome.failed_ids, covered_by: tests, kill_cause: outcome.kill_cause,
                                  executed: outcome.executed_ids)
        outcome.failed_ids.each { |id| plan.killers[id] += 1 }
        note_leftovers(plan.subject, "#{mutation.operator} #{result.digest}", outcome)
        @diagnostics.progress(result)
        result
      end

      # The tests that ran the edited code (a coarse edit spans the whole
      # body, so it gets every test of the method), prior killers first, then
      # fastest-first.
      def tests_for(plan, mutation)
        return self.class.prioritize(plan.tests, plan.killers) if mutation.coarse

        line_numbers = mutation.edits.flat_map { |edit| plan.subject.coverage_lines_for(edit) }.uniq
        tests = plan.tests & @map.tests_for_edit(plan.subject, line_numbers)
        branch_tests = @map.tests_for_branches(plan.subject, mutation.edits)
        tests &= branch_tests if branch_tests
        self.class.prioritize(tests, plan.killers)
      end

      def deadline(runtime)
        [@config["timeout_factor"] * runtime, @config["timeout_min"]].max
      end

      # What a subject no test ran gets. Load-only code is not "no coverage":
      # it ran, but no forked test can re-run it, so it gets its own status.
      def unloadable(candidates, subject, line_numbers = nil)
        return skip_all(candidates, subject, Selection::CoverageMap::PRELOADED) if @map.preloaded?(subject.file)
        return skip_all(candidates, subject, "no coverage") unless
          @map.ran_at_load?(subject.file, line_numbers || subject.coverage_lines)

        load_time_results(candidates, subject)
      end

      # A def-time macro's only callers ran while the app loaded: the
      # child re-evals the def, but closure consumers captured the
      # pristine definition, so no test can observe a mutant (#409).
      def load_only?(subject)
        !subject.is_a?(ConstantSubject) && @map.called_only_at_load?(subject.file, subject.start_line)
      end

      def load_time_results(candidates, subject)
        candidates.map do |mutation, text|
          MutantResult.new(subject: subject, mutation: mutation, status: :ran_at_load, mutated_source: text,
                           reason: Selection::CoverageMap::RAN_AT_LOAD)
        end
      end

      # One mutation whose edited lines no test ran (see unloadable).
      def uncoverable(plan, mutation, text)
        line_numbers = mutation.edits.flat_map { |edit| plan.subject.coverage_lines_for(edit) }.uniq
        result, = unloadable([[mutation, text]], plan.subject, line_numbers)
        return result if result.status == :ran_at_load
        return result unless @map.tests_for_branches(plan.subject, mutation.edits) == []

        skipped, = skip_all([[mutation, text]], plan.subject, "no coverage (branch not taken)")
        skipped
      end

      def run_mutant(plan, mutation, text, tests)
        timeout = timeout_for(tests, plan.slowdown)
        outcome = @runner.run(subject: plan.subject, text: text, test_ids: tests, timeout: timeout,
                              mutation: mutation, eval_prefix: eval_prefix(plan))
        outcome = calibrate(plan, mutation, text, tests, timeout) if outcome.status == :timeout
        flaky_check(plan, mutation, text, tests, outcome)
      end

      # --flaky-check (#476): one reordered confirmation run per decisive
      # fresh verdict. A disagreement is unverified - outside the score and
      # never cached - not "rerun until it passes". A reused verdict is
      # already trusted evidence and never reaches here. A budget-cut
      # outcome is already unverified and earns no second fork.
      def flaky_check(plan, mutation, text, tests, outcome)
        return outcome unless flaky_checkable?(outcome)
        return outcome if budget_spent?

        timeout = timeout_for(tests, plan.slowdown)

        rerun = @runner.run(subject: plan.subject, text: text, test_ids: reordered(tests),
                            timeout: timeout, mutation: mutation, eval_prefix: eval_prefix(plan))
        return outcome if rerun.status == outcome.status

        Execution::Runner::Outcome.new(status: :unverified, runtime: outcome.runtime + rerun.runtime,
                                       message: flaky_message(outcome, rerun))
      end

      # A shuffled order that is guaranteed to differ (a two-test shuffle
      # has even odds of coming out identical): order-dependence is exactly
      # what the confirmation run hunts.
      def reordered(tests)
        shuffled = tests.shuffle(random: Random.new(@config["seed"]))
        shuffled == tests && shuffled.size > 1 ? shuffled.rotate : shuffled
      end

      def flaky_checkable?(outcome)
        case @config["flaky_check"]
        when "survivors" then outcome.status == :survived
        when "decisive" then %i[survived killed].include?(outcome.status)
        else false
        end
      end

      def flaky_message(outcome, rerun)
        decisive = (outcome.failed_ids | rerun.failed_ids).first(3)
        named = decisive.empty? ? "" : " (decisive tests: #{decisive.join(', ')})"
        "flaky verdict: first #{outcome.status}, then #{rerun.status} on a reordered confirmation " \
          "run#{named} - the mutant is unverified, not #{outcome.status}"
      end

      # Each mutant is checked separately: changing a body can change which
      # definition a test reaches, so one unreachable verdict cannot skip later work.
      def note_unreachable(plan, outcome)
        @diagnostics.warn("#{plan.subject.id}: a mutant never ran and is not scored\n  #{outcome.message}")
      end

      # The text a known def-time wrapper needs re-evaluated with the def.
      # Sorbet's sig sits on the lines right before it; without it the def
      # evaluates alone and runtime type checks silently drop for the child.
      def eval_prefix(plan)
        return nil unless plan.wrapper == :sorbet

        plan.subject.sig_source
      end

      # Recorded durations come from one warm process; a fresh child can be
      # slower (lazy loading, first queries). So a timeout is checked at
      # once: the unchanged method runs the same tests with
      # baseline_timeout. If the deadline from that real runtime is longer,
      # the mutant runs again with it, and later mutants of the subject get
      # the measured slowdown. A timeout that remains is the mutant's own.
      # A --max-duration deadline caps every admission the scheduler makes:
      # verdict checks and timeout calibrations get only the time left.
      def budget_capped(timeout)
        return timeout unless @deadline

        remaining = @deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        remaining.clamp(0.0, timeout)
      end

      def budget_spent?
        @deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline
      end

      # A fresh kill whose check the budget skipped proves nothing yet: it
      # becomes unverified, outside the score, and is never cached.
      def unverifiable(result)
        return result if result.reused? || result.status != :killed

        result.as_unverified("verdict check skipped: the --max-duration budget is spent")
      end

      # A timeout the budget keeps the calibration from judging proves
      # nothing either: no zero-time forks, and a retry cut short does not
      # count as detected.
      def calibrate(plan, mutation, text, tests, timeout)
        if budget_spent?
          return unverified_outcome(timeout, "timeout calibration skipped: the --max-duration budget is spent")
        end

        unchanged, shortened = unchanged_timing(plan, tests)
        if unchanged.status == :timeout && shortened
          return unverified_outcome(unchanged.runtime, "the --max-duration budget cut the timeout calibration short")
        end
        return unchanged_failed(unchanged) unless unchanged.status == :survived

        retry_longer(plan, mutation, text, tests, [timeout, unchanged.runtime])
      end

      # The unchanged method under the budget-capped baseline timeout, and
      # whether the cap shortened it.
      def unchanged_timing(plan, tests)
        capped = budget_capped(@config["baseline_timeout"])
        outcome = @runner.run(subject: plan.subject, text: plan.subject.source, test_ids: tests,
                              timeout: capped, eval_prefix: eval_prefix(plan))
        note_leftovers(plan.subject, "timeout check", outcome)
        [outcome, capped < @config["baseline_timeout"]]
      end

      def retry_longer(plan, mutation, text, tests, limit)
        timeout, unchanged_runtime = limit
        recorded = @map.recorded_runtime(tests)
        plan.slowdown = [plan.slowdown, unchanged_runtime / recorded].max if recorded&.positive?
        longer = deadline(unchanged_runtime)
        return Execution::Runner::Outcome.new(status: :timeout, runtime: timeout) if longer <= timeout
        # The unchanged timing may have used the final allowance: no
        # zero-time retry fork (#296).
        if budget_spent?
          return unverified_outcome(timeout, "the --max-duration budget is spent before the mutant retry")
        end

        retry_timeout = budget_capped(longer)
        retried = @runner.run(subject: plan.subject, text: text, test_ids: tests, timeout: retry_timeout,
                              mutation: mutation, eval_prefix: eval_prefix(plan))
        return retried unless retried.status == :timeout && retry_timeout < longer

        unverified_outcome(retried.runtime, "the --max-duration budget cut the mutant retry short")
      end

      # A budget-cut calibration proves nothing about the mutant: outside
      # the score, and never cached.
      def unverified_outcome(runtime, message)
        Execution::Runner::Outcome.new(status: :unverified, runtime: runtime, message: message)
      end

      def unchanged_failed(unchanged)
        how = unchanged.status == :timeout ? "time out" : "fail"
        hint = unchanged.status == :timeout ? " (raise baseline_timeout)" : ""
        Execution::Runner::Outcome.new(status: :error, runtime: unchanged.runtime,
                                       message: "tests also #{how} with the method unchanged#{hint}")
      end

      # The method saboteur would redefine must be the one Ruby is running.
      # Returns [skip reason, wrapper]: a known def-time wrapper (sorbet's
      # sig is one, see Execution::Wrapper) is not a shadowing - the child
      # re-evaluates it together with the def, so the check passes.
      def load_problem(subject)
        return [nil, nil] unless @verify_loaded

        return [nil, nil] if @reevaluator.whole_file?(subject)

        owner = @reevaluator.resolve_owner(subject)
        target = subject.singleton ? owner.singleton_class : owner
        method = own_method(target, subject.name)
        return ["method not loaded", nil] unless method

        file, line = method.source_location
        if file && Selection::CoverageMap.canonical(file) == subject.file && line == subject.start_line
          return [nil, nil]
        end

        wrapper = Execution::Wrapper.around(method, file)
        return [nil, wrapper] if wrapper

        ["shadowed definition (runtime method at #{file}:#{line})#{WHOLE_FILE_HINT}", nil]
      rescue Error => e
        ["owner not loaded: #{e.message}#{WHOLE_FILE_HINT}", nil]
      end

      def own_method(target, name)
        return nil unless target.method_defined?(name) || target.private_method_defined?(name)

        method = target.instance_method(name)
        method = method.super_method while method && method.owner != target
        method
      end

      def note_leftovers(subject, what, outcome)
        return if outcome.leftover_pids.empty?

        @diagnostics.warn("#{subject.id} #{what}: killed #{outcome.leftover_pids.size} process(es) it left running")
      end

      def skip_all(candidates, subject, reason, covered_by: [])
        candidates.map do |mutation, text|
          MutantResult.new(subject: subject, mutation: mutation, status: :skipped, mutated_source: text,
                           reason: reason, covered_by: covered_by)
        end
      end
    end
  end
end
