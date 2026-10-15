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
        return if distribution.unreached.empty? && distribution.truncated.empty?

        reason = @budget_announced ? "max_duration" : "fail_fast"
        truncated = distribution.truncated.map { |subject, omitted| { subject: subject.id, omitted: omitted } }
        @early_stop = EarlyStop.new(reason: reason, unreached: distribution.unreached.map(&:id), truncated: truncated)
      end

      # max_duration was announced before fail_fast could stop the run: a
      # budget stop overrides a failure stop announced later.
      def run_early_stop_reason
        @budget_announced ? "max_duration" : "fail_fast"
      end
    end
  end
end
