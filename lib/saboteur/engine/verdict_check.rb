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

      def call(results)
        fresh = results.reject(&:reused?)
        failing_runs = failing_sequences(fresh.select { |result| named_kill?(result) })
        failing = failing_claims(fresh.select { |result| unnamed_kill?(result) })
        results.map { |result| checked(result, failing_runs, failing) }
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

      # Runs each distinct kill sequence once. Returns those that fail, each
      # with why (the failure message, when there is one).
      def failing_sequences(kills)
        kills.map { |result| sequence(result) }.uniq.each_with_object({}) do |tests, failing|
          outcome = @run_unchanged.call(tests, @baseline_timeout)
          failing[tests] = outcome.message unless outcome.status == :survived
        end
      end

      # Kills with no failing test named. Returns those that fail unchanged.
      def failing_claims(claims)
        claims.reject do |result|
          @run_unchanged.call(result.covered_by, @baseline_timeout).status == :survived
        end
      end

      def checked(result, failing_runs, failing)
        return result if result.reused?

        if named_kill?(result) && failing_runs.key?(sequence(result))
          why = failing_runs[sequence(result)]
          result.as_error("killing test #{sequence(result).last} also fails with the method unchanged" \
                          "#{": #{why}" if why}", rejected_kill: true)
        elsif failing.include?(result)
          result.as_error("tests also fail with the method unchanged", rejected_kill: true)
        else
          result
        end
      end
    end
  end
end
