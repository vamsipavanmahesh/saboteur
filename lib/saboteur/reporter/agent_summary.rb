# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "findings"
require_relative "survivor_hints"
require_relative "agent_incomplete"
require_relative "agent_clipping"

module Saboteur
  module Reporter
    module Agent
      # Builds the payload hash for one run: status, verdict, exit code, counts,
      # provenance, a few findings and the next commands.
      module Summary
        class << self
          include Clipping

          # Public entry first; the helpers below are private.
          def build(report, provenance, shown, snippet_limit)
            incomplete = Incomplete.reasons(report)
            status = status_of(report, incomplete)
            verdict = verdict_of(report, status)
            {
              version: VERSION, status: status, verdict: verdict, exitCode: exit_code_for(verdict),
              provenance: provenance_hash(provenance).merge(operatorPolicy: report.operator_policy),
              # killCauses is the assertion/crash split the text report prints
              # (#1045), so an agent can weigh the score without parsing prose.
              counts: counts(report), score: score(report), killCauses: report.score_breakdown.kill_causes_h,
              scoreDefinition: "(killed + timeout) / (killed + survived + timeout); null when nothing was tested",
              incomplete: incomplete, timeoutCountedAsDetected: report.counts[:timeout],
              findings: findings(report, shown, snippet_limit)
            }.merge(report.shard ? { shard: report.shard.to_h } : {}).merge(
              warnings: report.warnings.first(WARNING_LIMIT).map { |warning| warning.to_s[0, WARNING_LENGTH] },
              next: next_steps(report, provenance)
            )
          end

          private

          def status_of(report, incomplete)
            return "not_applicable" if report.results.empty? && incomplete.empty?

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

          def score(report) = report.score&.round(4)

          # Display values are clipped; the commands under next use the exact values or are left out.
          def provenance_hash(provenance)
            { ref: clip_value(provenance.ref, 120), seed: bounded_number(provenance.seed),
              head: clip_value(provenance.head, 64),
              workingTree: provenance.working_tree, changedFiles: provenance.changed_files,
              mode: provenance.mode, selection: selection_hash(provenance) }
          end

          # referenced: files that got their specs by constant reference or
          # require, not by name; a survivor there is read with that in mind.
          def selection_hash(provenance)
            %i[subjects tests sources].to_h { |key| [key, listing(provenance.public_send(key))] }
                                      .merge(referenced: listing(provenance.referenced.keys),
                                             config: clip_value(provenance.config_path, 120),
                                             digest: provenance.digest,
                                             settings: provenance.settings.transform_values { |v| clip_value(v, 120) })
          end

          def listing(list) = { count: list.size, first: list.first(3).map { |entry| clip_value(entry, 120) } }

          def findings(report, shown, snippet_limit)
            all = Findings.build(report)
            by_reference = report.referenced.keys
            live = report.unignored_survivors.size
            {
              survivors: live, shown: shown_findings(all[:survivors], shown, snippet_limit, by_reference),
              omitted: live - [shown, all[:survivors].size].min,
              accepted: report.survivors.size - live, ordering: all[:ordering],
              hintCaveat: SurvivorHints::CAVEAT
            }
          end

          # specsByReference: the file's specs were found by constant reference
          # or require, so a survivor there may only mean the spec is elsewhere.
          def shown_findings(listed, shown, snippet_limit, by_reference)
            listed.first(shown).map do |finding|
              finding.slice(:digest, :line, :endLine, :operator, :coarse, :classification)
                     .merge(path: clip_value(finding[:path], 200), subject: clip_value(finding[:subject], 200),
                            original: clip(finding[:original], snippet_limit),
                            replacement: clip(finding[:replacement], snippet_limit))
                     .merge(finding_hints(finding))
                     .merge(by_reference.include?(finding[:path]) ? { specsByReference: true } : {})
            end
          end

          def finding_hints(finding)
            structured = SurvivorHints.structured(operator: finding[:operator], original: finding[:original],
                                                  replacement: finding[:replacement], coarse: finding[:coarse])
            { hint: SurvivorHints.for(finding[:operator], coarse: finding[:coarse]) }.compact
                                                                                     .merge(testHint: structured)
          end

          def next_steps(report, provenance)
            steps = {}
            add_command(steps, :rerun, Commands.rerun(provenance))
            first = Findings.build(report)[:survivors].first
            if first
              replay = Commands.replay(provenance, first[:digest], survivors: report.survivors)
              add_command(steps, :replay, replay)
            end
            steps[:fullReport] = provenance.json_report if short_path?(provenance.json_report)
            steps
          end

          def short_path?(path)
            path && path.bytesize <= 400
          end

          def add_command(steps, key, command)
            steps[key] = command
            return if command

            steps[:"#{key}Unavailable"] =
              "command longer than #{Commands::MAX_BYTES} bytes; rebuild it from provenance"
          end
        end
      end
    end
  end
end
