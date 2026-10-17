# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # How a finished run maps to an exit code and a recorded exit cause. Mixed
    # into the CLI, which supplies `config` and the `@err` stream.
    module ExitStatus
      private

      # Last resort: a bug must not escape as a bare stack trace and an accidental exit 1.
      def internal_error(error)
        CrashReport.call(error, verbose: @verbose, agent: agent?, err: @err, out: @out, log_path: crash_log_path)
      end

      # The crash log lives with the other run state. A broken config (or a
      # nil cache_dir) must not swallow the crash report itself, so fall
      # back to no log.
      def crash_log_path
        dir = config.path("cache_dir")
        dir && File.join(dir, CrashReport::LOG_NAME)
      rescue StandardError
        nil
      end

      def exit_code(report)
        return EXIT_BUDGET if budget_exhausted?(report)

        return EXIT_TOOL if untested_partial?(report)

        return EXIT_TOOL if unverifiable_scope?(report)

        return EXIT_TOOL if mostly_errored?(report)

        return EXIT_TOOL if incomplete_under_threshold?(report)

        failed_quality_gate?(report) || gates.failed?(report, @err) ? EXIT_SURVIVORS : EXIT_OK
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

      # A scoped run whose subjects were all skipped (refinements, no
      # coverage, ...) verified none of the change under review; exit 0
      # with score n/a would green-light an untested change (#574).
      def unverifiable_scope?(report)
        return false unless unverifiable_review?(report)

        report.skipped_subjects.each do |subject, reason|
          @err.puts("saboteur: #{subject.id} was skipped (#{reason}), so the change under test was not verified")
        end
        true
      end

      def unverifiable_review?(report)
        report.review? && report.subjects.any? &&
          report.subjects.all? { |subject| report.skipped_subjects.key?(subject) }
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
        else
          if report.majority_errored?
            "errorMajority"
          elsif unverifiable_review?(report) || (report.early_stop && report.score_breakdown.tested.zero?)
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

        count = report.counts.values_at(*(gates.judges_errors? ? %i[resource_limit] : %i[error resource_limit])).sum
        @err.puts("saboteur: #{count} mutant(s) errored or hit a resource limit, so the score is incomplete") if
          count.positive?
        count.positive?
      end
    end
  end
  end
