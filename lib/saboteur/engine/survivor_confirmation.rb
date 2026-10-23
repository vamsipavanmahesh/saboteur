# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Post-run survivor confirmation (#1063): with partial_coverage=use the
    # coverage map can be a partial rebuild, so every open survivor's
    # covering specs the mutant never ran get one budgeted confirmation run
    # through the same Runner invocation the scheduler makes. A failing run
    # kills the mutant; a passing run marks the result confirmed; anything
    # that could not run is marked unconfirmed with the reason. The field is
    # additive - the status keeps its meaning - and no outcome is silent.
    class SurvivorConfirmation
      # The most covering specs one survivor re-runs; the config's
      # confirmation_budget caps the whole pass.
      MAX_SPECS_PER_SURVIVOR = 8

      def initialize(config:, map:, scheduler:, diagnostics:, budget_exceeded:, cache: nil, load_specs: ->(_files) {})
        @config = config
        @map = map
        @scheduler = scheduler
        @diagnostics = diagnostics
        @budget_exceeded = budget_exceeded
        @cache = cache
        @load_specs = load_specs
      end

      def call(results, ignore_list:, early_stop: nil)
        survivors = results.select { |result| result.survived? && !ignore_list.accepts?(result) }
        return results if survivors.empty?

        if early_stop
          @diagnostics.warn("survivor confirmation covers only the survivors reached before the run " \
                            "stopped early (#{early_stop.reason})")
        end
        @remaining = @config["confirmation_budget"]
        @map_silent = 0
        results.map { |result| survivors.include?(result) ? confirm(result) : result }
               .tap { |confirmed| summarize(confirmed) }
               .tap { warn_map_silent }
      end

      private

      # A crash while confirming one survivor downgrades it to unconfirmed
      # with one warning; it never ends the run (#1140).
      def confirm(result)
        confirm_checked(result)
      rescue RefusedSpecPath => e
        warn_refused(e)
        result.with_confirmation("unconfirmed_map(a covering spec from the whole-suite map was refused)")
      rescue StandardError => e
        warn_failed(result, e)
        unconfirmed(result, "confirmation failed: #{e.class}")
      end

      # The map named a spec that is not a spec file inside the project: the
      # map cannot be trusted, so its survivors stay counted (#1286).
      def warn_refused(error)
        return if @warned_refused

        @warned_refused = true
        @diagnostics.warn("survivor confirmation refused the whole-suite coverage map: " \
                          "#{error.message.lines.first.strip}; its survivors stay counted; " \
                          "run `saboteur run --all` to rebuild it")
      end

      # One line per run, however many survivors hit the same failure.
      def warn_failed(result, error)
        return if @warned_failure

        @warned_failure = true
        @diagnostics.warn("survivor confirmation failed for #{result.subject.id} #{result.digest} " \
                          "(#{error.class}: #{error.message.lines.map(&:strip).reject(&:empty?).first}); " \
                          "its survivors stay unconfirmed, outside the score")
      end

      def confirm_checked(result)
        return unconfirmed(result, "the confirmation budget is spent") if @remaining <= 0
        return unconfirmed(result, "the --max-duration budget is spent") if @budget_exceeded.call

        # Nothing in the whole-suite map covers the edited lines (the tree
        # drifted since the map was built): the map cannot confirm anything.
        covering = covering_tests(result)
        return map_silent(result) if covering.empty?

        tests = unrun_covering_tests(result, covering)
        return result.with_confirmation("confirmed") if tests.empty?

        load_unselected_specs(tests)
        outcome = run_confirmation(result, tests)
        @remaining -= outcome.runtime || 0
        case outcome.status
        when :killed then checked_kill(result, tests, outcome)
        when :survived then result.with_confirmation("confirmed",
                                                     executed: (result.executed || []) + outcome.executed_ids,
                                                     value_differed: merged_observation([result, outcome]))
        else unconfirmed(result, "the confirmation run #{outcome.status}: #{outcome.message}")
        end
      end

      # The whole-suite map's covering tests for the mutant's edited lines
      # (branch evidence intersected, mirroring the scheduler), minus the
      # tests the mutant already ran, fastest first, capped.
      def unrun_covering_tests(result, covering)
        fastest_first(covering - (result.executed || result.covered_by)).first(MAX_SPECS_PER_SURVIVOR)
      end

      # The covering specs may live in files this run never loaded; the
      # forked confirmation child can only run examples already in its world.
      def load_unselected_specs(tests)
        @load_specs.call(tests.map { |id| id.sub(/\[[\d:]+\]\z/, "") })
      end

      def covering_tests(result)
        line_numbers = result.mutation.edits.flat_map { |edit| result.subject.coverage_lines_for(edit) }.uniq
        tests = @map.tests_for_edit(result.subject, line_numbers)
        branch_tests = @map.tests_for_branches(result.subject, result.mutation.edits)
        branch_tests ? tests & branch_tests : tests
      end

      def fastest_first(tests)
        tests.sort_by { |id| @map.recorded_runtime([id]) || Float::INFINITY }
      end

      def run_confirmation(result, tests)
        @scheduler.runner.run(subject: result.subject, text: result.mutated_source, test_ids: tests,
                              timeout: timeout_for(tests, result), mutation: result.mutation,
                              eval_prefix: @scheduler.confirmation_prefix(result.subject))
      end

      # The value observation across every run against the mutant, initial
      # selection plus confirmation: any run that saw the value differ
      # decides, and a run that could not probe the site never erases
      # another run's observation (#1311). One pair argument: the merge is
      # order-insensitive, so no argument order exists for a test to pin.
      def merged_observation(runs)
        observations = runs.map(&:value_differed).compact
        return nil if observations.empty?

        observations.any?
      end

      # A kill keeps only a true observation: an assertion, not the value,
      # decided the verdict, so a not-differed run never reads as false (#1311).
      def kill_observation(runs)
        merged_observation(runs) || nil
      end

      # A confirmation kill stands only after the same VerdictCheck the
      # scheduler runs: the kill sequence, in order, must pass with the
      # method unchanged, so an order-dependent spec cannot convert a true
      # survivor into a credited kill (security review). A rejected kill
      # becomes an error; a check the budgets never let run comes back
      # unverified - outside the score and never cached.
      def checked_kill(result, tests, outcome)
        kill = result.with_confirmation(
          "killed_by_confirmation", status: :killed, reason: outcome.message, killed_by: outcome.failed_ids,
                                    covered_by: tests, kill_cause: outcome.kill_cause,
                                    runtime: (result.runtime || 0) + (outcome.runtime || 0),
                                    executed: (result.executed || []) + outcome.executed_ids,
                                    value_differed: kill_observation([result, outcome])
        )
        checked = VerdictCheck.new(run_unchanged: unchanged_runner(result.subject),
                                   baseline_timeout: @config["baseline_timeout"]).call([kill]).first
        return checked unless checked.status == :killed

        @diagnostics.inform("#{result.subject.id} #{result.mutation.operator} #{result.digest}: " \
                            "killed on confirmation by #{outcome.failed_ids.first}")
        record_kill(result, kill)
        checked
      end

      # The standing kill goes into the verdict cache with the mutant's full
      # covering test set, not the capped confirmation subset: the cache
      # fingerprint digests that set, so only the full set overwrites the
      # survivor verdict the run cached and lets the next run reuse the kill
      # (#1079). ResultCache#record replaces the subject+mutation entry, so
      # the stale survivor verdict cannot win a later lookup.
      def record_kill(result, kill)
        @cache&.record(kill.with_confirmation("killed_by_confirmation", covered_by: covering_tests(result)))
      end

      # The unchanged-method re-run VerdictCheck checks a kill against, in
      # the unchanged_runner shape (scheduler.rb), against the confirmation
      # and --max-duration budgets instead of the scheduler's plan state.
      def unchanged_runner(subject)
        lambda do |tests, timeout|
          if @remaining <= 0 || @budget_exceeded.call
            Execution::Runner::Outcome.new(status: :unverified, runtime: 0.0,
                                           message: "the confirmation budget is spent")
          else
            outcome = @scheduler.runner.run(subject: subject, text: subject.source, test_ids: tests,
                                            timeout: timeout,
                                            eval_prefix: @scheduler.confirmation_prefix(subject))
            @remaining -= outcome.runtime || 0
            outcome
          end
        end
      end

      # The map says nothing about the edited lines (the tree drifted since it
      # was built): the survivor stays counted and the pass says so once.
      def map_silent(result)
        @map_silent += 1
        result.with_confirmation("unconfirmed_map(no covering tests in the whole-suite map)")
      end

      def unconfirmed(result, reason)
        result.with_confirmation("unconfirmed(#{reason})")
      end

      # The scheduler's timeout_for shape with the post-run slowdown of 1.0.
      # recorded_runtime is nil without arm durations: fall back to the
      # mutant's own first-run runtime, then to the suite's mean.
      def timeout_for(tests, result)
        recorded = @map.recorded_runtime(tests) || result.runtime || suite_mean_runtime
        return @config["baseline_timeout"] unless recorded

        [@config["timeout_factor"] * recorded, @config["timeout_min"]].max
      end

      def suite_mean_runtime
        durations = @map.tests.map { |id| @map.recorded_runtime([id]) }.compact
        durations.empty? ? nil : durations.sum / durations.size
      end

      def warn_map_silent
        return if @map_silent.zero?

        @diagnostics.warn("survivor confirmation: the whole-suite coverage map covers none of the edited lines of " \
                          "#{@map_silent} survivor#{'s' unless @map_silent == 1}, so they stay counted; " \
                          "run `saboteur run --all` to rebuild it")
      end

      def summarize(results)
        counts = results.filter_map(&:confirmation).tally
        return if counts.empty?

        @diagnostics.inform("survivor confirmation: #{counts.map { |mark, n| "#{n} #{mark}" }.join(', ')}")
      end
    end
  end
end
