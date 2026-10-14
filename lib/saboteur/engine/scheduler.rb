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

      def initialize(config:, runner:, map:, reevaluator:, diagnostics:, cache: nil)
        @config = config
        @runner = runner
        @map = map
        @reevaluator = reevaluator
        @diagnostics = diagnostics
        @cache = cache
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

        plan = Plan.new(subject:, tests:, killers: Hash.new(0), slowdown: 1.0, wrapper: wrapper)
        reused = all_reused(plan, candidates)
        return reused if reused

        results = run_candidates(candidates) do |mutation, text|
          reuse(plan, mutation, text) || execute(plan, mutation, text)
        end
        checked(plan, results)
      end

      # The per-mutant timeout: timeout_factor times what the tests took
      # while the map was built (times the subject's measured slowdown), and
      # never less than timeout_min.
      def timeout_for(tests, slowdown = 1.0)
        recorded = @map.recorded_runtime(tests)
        return @config["baseline_timeout"] unless recorded

        deadline(recorded * slowdown)
      end

      private

      # Verdicts that did not hold up are warned about once per subject;
      # only checked verdicts are stored for --incremental.
      def checked(plan, results)
        subject = plan.subject
        run_unchanged = lambda do |tests, timeout|
          @runner.run(subject: subject, text: subject.source, test_ids: tests, timeout: timeout,
                      eval_prefix: eval_prefix(plan))
                 .tap { |outcome| note_leftovers(subject, "verdict check", outcome) }
        end
        check = VerdictCheck.new(run_unchanged: run_unchanged, baseline_timeout: @config["baseline_timeout"])
        final = check.call(results)
        final.reject(&:reused?).each { |result| @cache&.record(result) }
        overturned = final.zip(results).count { |after, before| !after.equal?(before) }
        if overturned.positive?
          @diagnostics.warn("#{subject.id}: #{overturned} verdict(s) failed with the method unchanged")
        end
        final
      end

      # When every verdict can be reused, nothing forks: not even the neutral
      # check. Returns the results, or nil at the first one that must run.
      def all_reused(plan, candidates)
        return nil unless @cache

        catch(:must_run) do
          run_candidates(candidates) { |mutation, text| reuse(plan, mutation, text) || throw(:must_run) }
        end
      end

      def run_candidates(candidates, &run_one)
        coarse, fine = candidates.partition { |mutation, _| mutation.coarse }
        results = coarse.map { |mutation, text| run_one.call(mutation, text) }
        results + fine.map { |mutation, text| run_one.call(mutation, text) }
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

      # What a subject no test ran gets. Code that only ran while the app
      # loaded is not "no coverage" - it ran - but no forked test can re-run
      # it, so it gets its own status, out of the score, with a hint.
      def unloadable(candidates, subject, line_numbers = nil)
        return skip_all(candidates, subject, "no coverage") unless
          @map.ran_at_load?(subject.file, line_numbers || subject.coverage_lines)

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
        outcome.status == :timeout ? calibrate(plan, mutation, text, tests, timeout) : outcome
      end

      # Each mutant is checked separately: changing a body can change which
      # definition a test reaches, so one unreachable verdict cannot skip later work.
      def note_unreachable(plan, outcome)
        @diagnostics.warn("#{plan.subject.id}: #{outcome.message}")
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
      def calibrate(plan, mutation, text, tests, timeout)
        unchanged = @runner.run(subject: plan.subject, text: plan.subject.source, test_ids: tests,
                                timeout: @config["baseline_timeout"], eval_prefix: eval_prefix(plan))
        note_leftovers(plan.subject, "timeout check", unchanged)
        return unchanged_failed(unchanged) unless unchanged.status == :survived

        recorded = @map.recorded_runtime(tests)
        plan.slowdown = [plan.slowdown, unchanged.runtime / recorded].max if recorded&.positive?
        longer = deadline(unchanged.runtime)
        return Execution::Runner::Outcome.new(status: :timeout, runtime: timeout) if longer <= timeout

        @runner.run(subject: plan.subject, text: text, test_ids: tests, timeout: longer, mutation: mutation,
                    eval_prefix: eval_prefix(plan))
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
