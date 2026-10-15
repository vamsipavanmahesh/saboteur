# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Checks each kill against the method re-evaluated unchanged: a kill
    # stands only if the same tests, in the same order, up to and including
    # the last killer, pass without the mutant (so a test that fails only after
    # another test left state behind cannot claim a kill). A kill with no
    # failing test named (an exit, a suite-level failure) is checked on all
    # the mutant's tests. A kill that fails the check becomes an error.
    # (Timeouts are checked by the scheduler as they happen.)
    #
    # This re-runs the evidence, not every covering test: a method that every
    # factory calls can have hundreds of tests, and killer-first ordering
    # makes most kills a single test.
    class VerdictCheck
      # run_unchanged: runs tests against the unchanged method,
      #   ->(test_ids, timeout) { Runner::Outcome }.
      def initialize(run_unchanged:, baseline_timeout:)
        @run_unchanged = run_unchanged
        @baseline_timeout = baseline_timeout
      end

      # Why a result the budget never let the check run is not a verdict.
      BUDGET_REASON = "the --max-duration budget stopped the verdict check before it could run"

      def call(results)
        fresh = results.reject(&:reused?)
        failing_runs, unchecked_runs = check_sequences(fresh.select { |result| named_kill?(result) })
        failing, unchecked = check_claims(fresh.select { |result| unnamed_kill?(result) })
        results.map { |result| checked(result, failing_runs, failing, unchecked_runs, unchecked) }
      end

      private

      def named_kill?(result)
        result.status == :killed && result.killed_by.any?
      end

      def unnamed_kill?(result)
        result.status == :killed && result.killed_by.empty?
      end

      # The tests the mutant ran, in order, up to and including the last
      # killer: a matrix run lists every failing test, and each of them must
      # pass under the unchanged method in this same sequence.
      def sequence(result)
        position = result.killed_by.filter_map { |test| result.covered_by.index(test) }.max
        position ? result.covered_by.first(position + 1) : [result.killed_by.first]
      end

      # Runs each distinct kill sequence once. Returns [failing, unchecked]:
      # failing maps a sequence to why it failed unchanged, unchecked maps
      # the sequences the budget never let run to why - an unverified re-run
      # is not a rejection (#296).
      def check_sequences(kills)
        failing = {}
        unchecked = {}
        kills.map { |result| sequence(result) }.uniq.each do |tests|
          outcome = @run_unchanged.call(tests, @baseline_timeout)
          if outcome.status == :unverified
            unchecked[tests] = outcome.message
          elsif outcome.status != :survived
            failing[tests] = outcome.message
          end
        end
        [failing, unchecked]
      end

      # Kills with no failing test named, checked on all their tests.
      # Returns [failing, unchecked]: failing maps a rejected result to why
      # it failed unchanged, unchecked maps a result the budget never let
      # run to why.
      def check_claims(claims)
        failing = {}
        unchecked = {}
        claims.each do |result|
          outcome = @run_unchanged.call(result.covered_by, @baseline_timeout)
          if outcome.status == :unverified
            unchecked[result] = outcome.message
          elsif outcome.status != :survived
            failing[result] = outcome.message
          end
        end
        [failing, unchecked]
      end

      def checked(result, failing_runs, failing, unchecked_runs, unchecked)
        return result if result.reused?
        return checked_named(result, failing_runs, unchecked_runs) if named_kill?(result)

        if failing.key?(result)
          why = failing[result]
          result.as_error("tests also fail with the method unchanged#{": #{why}" if why}", rejected_kill: true)
        elsif unchecked.key?(result)
          result.as_unverified(unchecked[result] || BUDGET_REASON)
        else
          result
        end
      end

      def checked_named(result, failing_runs, unchecked_runs)
        tests = sequence(result)
        if failing_runs.key?(tests)
          why = failing_runs[tests]
          result.as_error("killing test #{tests.last} also fails with the method unchanged" \
                          "#{": #{why}" if why}", rejected_kill: true)
        elsif unchecked_runs.key?(tests)
          result.as_unverified(unchecked_runs[tests] || BUDGET_REASON)
        else
          result
        end
      end
    end
  end
end
