# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    module Agent
      # What makes a verdict cover less than the whole selection. Each reason has a
      # stable code, a count and a plain meaning.
      module Incomplete
        NO_COVERAGE = "no coverage"

        class << self
          def reasons(report)
            reasons = []
            add(reasons, "no_coverage", skipped_for_coverage(report), "subjects or mutants had no covering test")
            load_only = report.counts[:ran_at_load] + report.skipped_subjects.values.count do |reason|
              reason == Selection::CoverageMap::RAN_AT_LOAD
            end
            add(reasons, "unsupported", unsupported_subjects(report),
                "subjects were skipped as unsupported (for example defined inside a block); no mutant was judged")
            add(reasons, "ran_at_load", load_only, "code ran only at load; no mutant was judged")
            add(reasons, "unreachable", report.counts[:unreachable], "tests did not call the replacement definition")
            add(reasons, "mutant_cap", omitted_by_cap(report), "mutants omitted by max_mutants_per_method")
            add(reasons, "errors", report.counts[:error], "mutants errored; their verdict did not hold up")
            add(reasons, "resource_limit", report.counts[:resource_limit], "mutants hit the memory or process cap")
            early_stop_reason(reasons, report)
            inline_scope(reasons, report)
            reasons
          end

          private

          def early_stop_reason(reasons, report)
            stop = report.early_stop
            return unless stop

            label = stop.reason == "fail_fast" ? "--fail-fast stopped" : "the --max-duration budget stopped"
            add(reasons, stop.reason, stop.unreached.size, "selected subjects did not run because #{label} the run")
          end

          def inline_scope(reasons, report)
            add(reasons, "inline_suppressed", report.inline_suppressions.size,
                "candidates were suppressed by inline directives; see the full report audit")
          end

          def add(reasons, code, count, meaning)
            reasons << { reason: code, count: count, meaning: meaning } if count.positive?
          end

          def skipped_for_coverage(report)
            report.skipped_subjects.values.count(NO_COVERAGE) + report.counts[:skipped]
          end

          def unsupported_subjects(report)
            report.skipped_subjects.values.count do |reason|
              reason != NO_COVERAGE && reason != Selection::CoverageMap::RAN_AT_LOAD
            end
          end

          def omitted_by_cap(report)
            report.warnings.sum { |warning| warning[/omitted (\d+) mutant/, 1].to_i }
          end
        end
      end
    end
  end
end
