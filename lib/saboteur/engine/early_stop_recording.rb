# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Records the subjects an early stop left behind - whole subjects that
    # never started and candidates skipped mid-way through a subject - so
    # the report says the verdict covers less than the selection.
    module EarlyStopRecording
      private

      # The subjects a stop left unrun or mid-way: the verdict covers less than the selection.
      def record_early_stop(distribution, planned_mutants: nil)
        return if distribution.unreached.empty? && distribution.truncated.empty? && distribution.unverified.empty?

        truncated = distribution.truncated.map { |subject, omitted| { subject: subject.id, omitted: omitted } }
        @early_stop = EarlyStop.new(reason: stop_reason(distribution), unreached: distribution.unreached.map(&:id),
                                    truncated: truncated, unverified: distribution.unverified.map(&:id),
                                    planned_mutants: planned_mutants)
      end

      # Mid-subject omissions are budget work. Unverified checks are budget
      # work only when the budget is actually spent (#296); without a spent
      # budget they come from a flaky-check rerun disagreement (#476), and
      # blaming --max-duration would be a lie (#1167). Only a stop that left
      # whole subjects unreached can be fail_fast's.
      def stop_reason(distribution)
        return "max_duration" if distribution.truncated.any?
        return "max_duration" if distribution.unverified.any? && budget_exceeded?
        return "unverified" if distribution.unverified.any? && distribution.unreached.empty?

        run_early_stop_reason
      end

      # max_duration was announced before fail_fast could stop the run: a
      # budget stop overrides a failure stop announced later.
      def run_early_stop_reason
        @budget_announced ? "max_duration" : "fail_fast"
      end

      # A baseline or coverage phase stopped because --max-duration ate its
      # allowance: budget exhaustion, not a broken suite. The run reports
      # partial with every selected subject unreached (exit 4) (#296).
      def budget_phase_stop(error, subjects)
        @diagnostics.warn(error.message)
        @early_stop = EarlyStop.new(reason: "max_duration", unreached: subjects.map(&:id), truncated: [],
                                    unverified: [])
        []
      end
    end
  end
end
