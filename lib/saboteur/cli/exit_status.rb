# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # How a finished run maps to an exit code and a recorded exit cause. Mixed
    # into the CLI, which supplies `config` and the `@err` stream.
    module ExitStatus
      private

      def exit_code(report)
        return EXIT_TOOL if mostly_errored?(report)

        return EXIT_TOOL if incomplete_under_threshold?(report)

        failed_quality_gate?(report) || gates.failed?(report, @err) ? EXIT_SURVIVORS : EXIT_OK
      end

      def gates = (@gates ||= Gates.new(config))

      def mostly_errored?(report)
        return false unless report.majority_errored?

        executed = report.executed
        errors = executed.count { |result| result.status == :error }
        @err.puts("saboteur: #{errors} of #{executed.size} mutants errored, so the run tested almost nothing; " \
                  "fix the errors and run again")
        true
      end

      # Agent mode: the recorded cause is the payload's own verdict, so the
      # JSON and the process exit classify the run the same way. An
      # incomplete run that mostly errored keeps its distinct cause, so the
      # harness rule means the same thing in both modes.
      def agent_exit_cause(report, payload)
        case payload[:verdict]
        when "clean" then "ok"
        when "survivors" then report.early_stop ? "failFast" : "survivors"
        else report.majority_errored? ? "errorMajority" : "incomplete"
        end
      end

      # Why the run exits the way it does, recorded in the JSON report so an
      # outer harness can tell "most mutants errored" from the other exit 3s.
      def exit_cause(report, code)
        case code
        when EXIT_OK then "ok"
        when EXIT_SURVIVORS then survivors_cause(report)
        else report.majority_errored? ? "errorMajority" : "incompleteUnderThreshold"
        end
      end

      # A run stopped by --fail-fast always exits 1: it stopped on a survivor, and
      # its score covers only the subjects that ran, so no threshold can pass it.
      def survivors_cause(report)
        return "failFast" if report.early_stop

        gates.cause || (config["threshold"].nil? ? "survivors" : "belowThreshold")
      end

      # With --threshold the score decides; without it any unignored survivor does.
      def failed_quality_gate?(report)
        return true if report.early_stop

        threshold = config["threshold"]
        return report.unignored_survivors.any? if threshold.nil?

        score = report.score
        return missing_score_reported? if score.nil?

        score * 100 < threshold
      end

      # A gate that cannot measure a score must not pass: CI would go green
      # on a run that tested nothing.
      def missing_score_reported?
        @err.puts("saboteur: no mutant was tested, so there is no score to compare with --threshold")
        true
      end

      # Errors and resource limits are outside the score. With a threshold they
      # make the run incomplete, so the score alone cannot pass it.
      def incomplete_under_threshold?(report)
        return false if config["threshold"].nil?

        count = report.counts.values_at(*(gates.judges_errors? ? %i[resource_limit] : %i[error resource_limit])).sum
        @err.puts("saboteur: #{count} mutant(s) errored or hit a resource limit, so the score is incomplete") if
          count.positive?
        count.positive?
      end
    end
  end
end
