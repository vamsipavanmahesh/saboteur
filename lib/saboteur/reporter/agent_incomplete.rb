# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    module Agent
      # What makes a verdict cover less than the whole selection. Each reason has a
      # stable code, a count and a plain meaning.
      module Incomplete
        NO_COVERAGE = "no coverage"
        SYNTAX_FAILURE = "invalid_file_syntax"
        UNREADABLE_FAILURE = "unreadable"

        # The only reason that leaves a run complete: the author suppressed
        # candidates inline, on purpose. Every other reason can drop a survivor.
        BENIGN = %w[inline_suppressed].freeze

        class << self
          # True when the run judged everything it selected (the saboteur.complete
          # flag in the JSON report): what an action may rely on before it removes
          # a review comment because its survivor is no longer reported.
          def complete?(report)
            reasons(report).all? { |reason| BENIGN.include?(reason[:reason]) }
          end

          def reasons(report)
            reasons = []
            shard_reason(reasons, report)
            add(reasons, "no_coverage", skipped_for_coverage(report), "subjects or mutants had no covering test")
            add(reasons, "unsupported", unsupported_subjects(report),
                "subjects were skipped as unsupported (for example defined inside a block); no mutant was judged")
            add(reasons, "ran_at_load", load_only_subjects(report), "code ran only at load; no mutant was judged")
            # A file loaded before Coverage.start has no attribution at all:
            # not unsupported (the shape is fine) and not ran_at_load (the
            # load-only evidence does not exist) - its own code (#688).
            add(reasons, "preloaded", preloaded_subjects(report),
                "files loaded before coverage started; their subjects could not be attributed to tests; " \
                "no mutant was judged")
            add(reasons, "unreachable", report.counts[:unreachable], "tests did not call the replacement definition")
            add(reasons, "mutant_cap", omitted_by_cap(report), "mutants omitted by max_mutants_per_method")
            add(reasons, "errors", report.counts[:error], "mutants errored; their verdict did not hold up")
            add(reasons, "resource_limit", report.counts[:resource_limit], "mutants hit the memory or process cap")
            unverified_reasons(reasons, report)
            discovery_failures(reasons, report)
            early_stop_reason(reasons, report)
            inline_scope(reasons, report)
            reasons
          end

          private

          # A shard always runs a subset of the planned inventory by contract, even
          # when this shard happened to select every planned mutant (count 0).
          def shard_reason(reasons, report)
            shard = report.shard
            return unless shard

            reasons << { reason: "shard", count: shard.planned_count - shard.selected_count,
                         meaning: "planned mutants assigned to other shards" }
          end

          # Source the selection could not read at all: its subjects never
          # entered the run, so a clean or complete verdict would be wrong.
          def discovery_failures(reasons, report)
            failures = report.discovery_failures
            add(reasons, SYNTAX_FAILURE, failures.count { |f| f.reason == SYNTAX_FAILURE },
                "included files did not parse; their subjects were not discovered")
            add(reasons, UNREADABLE_FAILURE, failures.count { |f| f.reason == UNREADABLE_FAILURE },
                "included untracked files could not be read; their subjects were not covered")
          end

          def unverified_reasons(reasons, report)
            flaky = report.results.count(&:flaky?)
            add(reasons, "unverified", report.counts[:unverified] - flaky,
                "mutants the --max-duration budget left unverified; their kills are not confirmed")
            add(reasons, "flaky", flaky,
                "mutants gave a different verdict on the --flaky-check reordered rerun; they are unverified")
          end

          def early_stop_reason(reasons, report)
            stop = report.early_stop
            return unless stop

            label = stop.reason == "fail_fast" ? "--fail-fast stopped" : "the --max-duration budget stopped"
            add(reasons, stop.reason, stop.unreached.size, "selected subjects did not run because #{label} the run")
            omitted = stop.truncated.sum { |entry| entry[:omitted] }
            add(reasons, "#{stop.reason}_truncated", omitted,
                "mutants omitted inside subjects that stopped mid-way because #{label} the run")
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

          # Load-only mutants plus the subjects skipped for the same reason.
          def load_only_subjects(report)
            report.counts[:ran_at_load] + report.skipped_subjects.values.count do |reason|
              reason == Selection::CoverageMap::RAN_AT_LOAD
            end
          end

          def preloaded_subjects(report)
            report.skipped_subjects.values.count(Selection::CoverageMap::PRELOADED)
          end

          def unsupported_subjects(report)
            report.skipped_subjects.values.count do |reason|
              reason != NO_COVERAGE && reason != Selection::CoverageMap::RAN_AT_LOAD &&
                reason != Selection::CoverageMap::PRELOADED
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
