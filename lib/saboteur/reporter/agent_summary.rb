# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "findings"
require_relative "agent_incomplete"

module Saboteur
  module Reporter
    module Agent
      # Builds the payload hash for one run: status, verdict, exit code, counts,
      # provenance, a few findings and the next commands.
      module Summary
        class << self
          # Public entry first; the helpers below are private.
          def build(report, provenance, shown, snippet_limit)
            incomplete = Incomplete.reasons(report)
            status = status_of(report, incomplete)
            verdict = verdict_of(report, status)
            {
              version: VERSION, status: status, verdict: verdict, exitCode: exit_code_for(verdict),
              provenance: provenance_hash(provenance),
              counts: counts(report), score: score(report),
              scoreDefinition: "(killed + timeout) / (killed + survived + timeout); null when nothing was tested",
              incomplete: incomplete, timeoutCountedAsDetected: report.counts[:timeout],
              findings: findings(report, shown, snippet_limit),
              warnings: warnings(report),
              next: next_steps(report, provenance)
            }
          end

          private

          def status_of(report, incomplete)
            return "not_applicable" if report.results.empty? && report.skipped_subjects.empty?

            incomplete.empty? ? "complete" : "partial"
          end

          def verdict_of(report, status)
            return "survivors" if report.unignored_survivors.any?

            { "complete" => "clean", "partial" => "incomplete", "not_applicable" => "not_applicable" }.fetch(status)
          end

          def exit_code_for(verdict)
            case verdict
            when "clean" then EXIT_CLEAN
            when "survivors" then EXIT_REVIEW
            else EXIT_INCOMPLETE
            end
          end

          def counts(report)
            report.counts.transform_keys { |status| camel(status) }.merge(executed: report.executed.size)
          end

          def camel(status)
            status.to_s.gsub(/_(\w)/) { Regexp.last_match(1).upcase }.to_sym
          end

          def score(report)
            report.score&.round(4)
          end

          def provenance_hash(provenance)
            { ref: provenance.ref, seed: provenance.seed, head: provenance.head,
              workingTree: provenance.working_tree, mode: provenance.mode }
          end

          def findings(report, shown, snippet_limit)
            all = Findings.build(report)
            live = report.unignored_survivors.size
            {
              survivors: live, shown: shown_findings(all[:survivors], shown, snippet_limit),
              omitted: live - [shown, all[:survivors].size].min,
              accepted: report.survivors.size - live, ordering: all[:ordering]
            }
          end

          def shown_findings(listed, shown, snippet_limit)
            listed.first(shown).map do |finding|
              finding.slice(:digest, :path, :line, :endLine, :subject, :operator, :coarse)
                     .merge(original: clip(finding[:original], snippet_limit),
                            replacement: clip(finding[:replacement], snippet_limit))
            end
          end

          def clip(text, limit)
            return "" if limit.zero?

            text.length > limit ? "#{text[0, limit]}..." : text
          end

          def warnings(report)
            report.warnings.first(WARNING_LIMIT).map { |warning| warning.to_s[0, WARNING_LENGTH] }
          end

          def next_steps(report, provenance)
            steps = { rerun: rerun_command(provenance) }
            first = Findings.build(report)[:survivors].first
            steps[:replay] = "saboteur run --id #{first[:digest]} --seed #{provenance.seed}" if first
            steps[:fullReport] = provenance.json_report if provenance.json_report
            steps
          end

          def rerun_command(provenance)
            since = provenance.ref ? " --since #{provenance.ref}" : ""
            "saboteur run --agent#{since} --seed #{provenance.seed}"
          end
        end
      end
    end
  end
end
