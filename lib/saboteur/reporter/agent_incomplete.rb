# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    module Agent
      # What makes a verdict cover less than the whole selection. Each reason has a
      # stable code, a count and a plain meaning.
      module Incomplete
        class << self
          def reasons(report)
            reasons = []
            add(reasons, "no_coverage", skipped_for_coverage(report), "subjects or mutants had no covering test")
            add(reasons, "mutant_cap", omitted_by_cap(report), "mutants omitted by max_mutants_per_method")
            add(reasons, "errors", report.counts[:error], "mutants errored; their verdict did not hold up")
            add(reasons, "resource_limit", report.counts[:resource_limit], "mutants hit the memory or process cap")
            reasons
          end

          private

          def add(reasons, code, count, meaning)
            reasons << { reason: code, count: count, meaning: meaning } if count.positive?
          end

          def skipped_for_coverage(report)
            report.skipped_subjects.size + report.counts[:skipped]
          end

          def omitted_by_cap(report)
            report.warnings.sum { |warning| warning[/omitted (\d+) mutant/, 1].to_i }
          end
        end
      end
    end
  end
end
