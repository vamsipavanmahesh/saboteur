# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "survivor_ranking"
require_relative "survivor_classification"

module Saboteur
  module Reporter
    # Findings for a code-review surface such as the saboteur GitHub Action:
    # a bounded list of survivors with everything a note on the pull-request
    # diff needs (file, line, digest, operator, original and replacement).
    # Survivors accepted on the ignore list are listed apart, with their
    # reason. The full, unbounded mutant data stays in the report's files
    # section; survivorsTruncated says how many more findings live only there.
    # The uncapped ranked digest list lets offline readers (the survivors
    # command) print the terminal's ordering without recomputing it (#1150).
    module Findings
      VERSION = 1

      # GitHub shows at most 10 annotations of one kind per step.
      LIMIT = 10

      ORDERING = SurvivorRanking::ORDERING

      class << self
        def build(report)
          live, accepted = report.survivors.partition { |result| result.ignored.nil? }
          {
            version: VERSION,
            ordering: ORDERING,
            limit: LIMIT,
            survivors: listed(report, live),
            survivorsTruncated: truncated(live),
            accepted: listed(report, accepted),
            acceptedTruncated: truncated(accepted),
            order: full_order(report, live, accepted)
          }
        end

        private

        def listed(report, results)
          ordered(report, results).first(LIMIT).map { |result| finding(report, result) }
        end

        def truncated(results)
          [results.size - LIMIT, 0].max
        end

        # Every survivor digest in terminal order: live ranked first, then
        # accepted - uncapped, unlike the findings lists themselves.
        def full_order(report, live, accepted)
          (ordered(report, live) + ordered(report, accepted)).map(&:digest)
        end

        def ordered(report, results)
          SurvivorRanking.ordered(report, results)
        end

        def finding(report, result)
          entries = edit_entries(result)
          entry = {
            digest: result.digest,
            path: path(report, result),
            line: entries.map { |edit| edit[:line] }.min,
            endLine: entries.map { |edit| edit[:endLine] }.max,
            subject: result.subject.id,
            operator: result.mutation.operator,
            original: joined_texts(result) { |edit| original_text(result, edit) },
            replacement: joined_texts(result, &:replacement),
            edits: entries,
            coarse: result.mutation.coarse,
            # Why the survivor is worth a look, as a label only (#192).
            classification: SurvivorClassification.label(result)
          }.compact
          entry = with_changed_lines(report, result, entry)
          result.ignored ? entry.merge(reason: result.ignored) : entry
        end

        # In diff mode, the changed lines the mutant touches. line above is where
        # the mutated statement starts, which can be above the changed line.
        def with_changed_lines(report, result, entry)
          lines = report.changed_lines_for(result)
          lines.empty? ? entry : entry.merge(changedLines: lines)
        end

        # Subject#apply applies edits in start-byte order; findings use the
        # same order, so an unsorted edit list from a custom mutation source
        # still gets a sane range and one entry per edit.
        def sorted_edits(result)
          result.mutation.edits.sort_by(&:start_byte)
        end

        # Stryker joins a multi-edit mutant's replacements the same way, so
        # both reports describe one mutant with one text.
        def joined_texts(result, &pick)
          sorted_edits(result).map { |edit| safe_text(pick.call(edit)) }.join(" | ")
        end

        # One entry per edit, so a multi-edit finding can point each joined
        # text at its own spot on the diff.
        def edit_entries(result)
          sorted_edits(result).map do |edit|
            {
              line: result.subject.line_of(edit.start_byte),
              endLine: result.subject.line_of([edit.end_byte - 1, edit.start_byte].max),
              original: safe_text(original_text(result, edit)),
              replacement: safe_text(edit.replacement)
            }
          end
        end

        def original_text(result, edit)
          result.subject.file_source.byteslice(edit.start_byte, edit.end_byte - edit.start_byte)
        end

        # A byte slice of source may be invalid UTF-8, which JSON cannot hold.
        def safe_text(text)
          text.dup.force_encoding(Encoding::UTF_8).scrub
        end

        def path(report, result)
          result.subject.file.delete_prefix("#{report.root}/")
        end
      end
    end
  end
end
