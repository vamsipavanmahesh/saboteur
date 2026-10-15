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
      def record_early_stop(distribution)
        return if distribution.unreached.empty? && distribution.truncated.empty? && distribution.unverified.empty?

        truncated = distribution.truncated.map { |subject, omitted| { subject: subject.id, omitted: omitted } }
        @early_stop = EarlyStop.new(reason: stop_reason(distribution), unreached: distribution.unreached.map(&:id),
                                    truncated: truncated, unverified: distribution.unverified.map(&:id))
      end

      # Mid-subject omissions and skipped checks are budget work: only a
      # stop that left whole subjects unreached can be fail_fast's.
      def stop_reason(distribution)
        return "max_duration" if distribution.truncated.any? || distribution.unverified.any?

        run_early_stop_reason
      end

      # max_duration was announced before fail_fast could stop the run: a
      # budget stop overrides a failure stop announced later.
      def run_early_stop_reason
        @budget_announced ? "max_duration" : "fail_fast"
      end
    end
  end
end
