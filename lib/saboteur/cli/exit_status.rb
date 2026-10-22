# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "flaky_exit"

module Saboteur
  class CLI
    # How a finished run maps to an exit code and a recorded exit cause. Mixed
    # into the CLI, which supplies `config` and the `@err` stream.
    module ExitStatus
      include FlakyExit

      private

      def exit_code(report)
        return EXIT_BUDGET if budget_exhausted?(report)

        return EXIT_OK if ignore_empty_diff?(report)

        return EXIT_TOOL if untested_partial?(report)

        return EXIT_TOOL if unverifiable_scope?(report) || flaky_disagreement?(report)

        return EXIT_TOOL if mostly_errored?(report)

        return EXIT_TOOL if incomplete_under_threshold?(report)

        quality_failed = failed_quality_gate?(report)
        gates.failed?(report, @err, record_cause: !quality_failed) || quality_failed ? EXIT_SURVIVORS : EXIT_OK
      end

      # --ignore-empty: a --since diff that selected no mutants exits 0 with
      # a note; suppressed, omitted or undiscovered mutants still gate.
      def ignore_empty_diff?(report)
        return false unless config["ignore_empty"] && config["since"] && report.results.empty?
        return false unless report.omissions.empty? && report.inline_suppressions.empty? &&
                            report.discovery_failures.empty?

        @err.puts("saboteur: no mutants in the diff - nothing to gate (--ignore-empty)")
        true
      end

      # A spent --max-duration budget exits 4 on its own, before the gates:
      # the run is partial by design, and --max-duration-ok opts back into
      # the plain verdict.
      def budget_exhausted?(report)
        report.early_stop&.reason == "max_duration" && !config["max_duration_ok"]
      end

      # A run stopped before any mutant was tested has no verdict to fall
      # back on: --max-duration-ok must not turn it green. Unverified
      # results are not tested verdicts, so an unverified-only stop has no
      # score either (#296). Exit 3, like the other incomplete shapes.
      def untested_partial?(report)
        return false unless report.early_stop && report.score_breakdown.tested.zero?

        @err.puts("saboteur: the run stopped before any mutant was tested, so there is no score to judge")
        true
      end

      # A run that verified none of the change under review - every
      # subject skipped (refinements, no coverage, ..., #574) or every
      # mutant unreachable (a suite re-loading mutated files, #597) -
      # must not exit 0 with score n/a and green-light an untested change.
      def unverifiable_scope?(report)
        if unverifiable_review?(report)
          # A text run already printed each skip up front; json and agent
          # runs read this sentence as the exit explanation (#1227).
          skips = %w[json agent].include?(@format) ? report.skipped_subjects : report.unannounced_skips
          skips.each { |subject, reason| @err.puts(subject.skipped_gate_sentence(reason, report.root)) }
          return true
        end
        return false unless unverifiable_unreachable?(report)

        @err.puts("saboteur: all mutants ran unreachable, so the change under test was not verified")
        true
      end

      def unverifiable_review?(report)
        report.review? && report.subjects.any? &&
          report.subjects.all? { |subject| report.skipped_subjects.key?(subject) }
      end

      def unverifiable_unreachable?(report)
        report.executed.any? && report.executed.all? { |result| result.status == :unreachable }
      end

      def gates = (@gates ||= Gates.new(config))

      def mostly_errored?(report)
        return false unless report.majority_errored?

        errored = report.executed.select { |result| result.status == :error }
        @err.puts("saboteur: fix the errors and run again\n  #{errored.size} of #{report.executed.size} " \
                  "mutants errored, so the run tested almost nothing#{ErrorCause.line(errored)}")
        true
      end

      # Agent mode: the recorded cause is the payload's own verdict, so the
      # JSON and the process exit classify the run the same way. An
      # incomplete run that mostly errored keeps its distinct cause, so the
      # harness rule means the same thing in both modes.
      def agent_exit_cause(report, payload)
        return "budgetExhausted" if budget_exhausted?(report)

        case payload[:verdict]
        when "clean" then "ok"
        when "survivors" then report.early_stop&.reason == "fail_fast" ? "failFast" : "survivors"
        else report.majority_errored? ? "errorMajority" : "incomplete"
        end
      end

      # Why the run exits the way it does, recorded in the JSON report so an
      # outer harness can tell "most mutants errored" from the other exit 3s.
      def exit_cause(report, code)
        case code
        when EXIT_OK then "ok"
        when EXIT_BUDGET then "budgetExhausted"
        when EXIT_SURVIVORS then survivors_cause(report)
        when EXIT_BASELINE_RED, EXIT_CRASH then ErrorCause.cause(code)
        else
          if report.majority_errored?
            "errorMajority"
          elsif unverifiable_review?(report) || unverifiable_unreachable?(report) || report.results.any?(&:flaky?) ||
                (report.early_stop && report.score_breakdown.tested.zero?)
            "incomplete"
          else
            "incompleteUnderThreshold"
          end
        end
      end

      # A run stopped by --fail-fast always exits 1: it stopped on a survivor, and
      # its score covers only the subjects that ran, so no threshold can pass it.
      def survivors_cause(report)
        return "failFast" if report.early_stop&.reason == "fail_fast"

        gates.cause || (config["threshold"].nil? ? "survivors" : "belowThreshold")
      end

      # With --threshold the score decides; without it any unignored survivor does.
      def failed_quality_gate?(report)
        return true if report.early_stop&.reason == "fail_fast"

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

        statuses = gates.judges_errors? ? %i[resource_limit] : %i[error resource_limit]
        problem = report.results.select { |result| statuses.include?(result.status) }
        @err.puts(ErrorCause.incomplete(problem)) if problem.any?
        problem.any?
      end
    end
  end
end
