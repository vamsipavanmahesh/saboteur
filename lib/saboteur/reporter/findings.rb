# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Findings for a code-review surface such as the saboteur GitHub Action:
    # a bounded list of survivors with everything a note on the pull-request
    # diff needs (file, line, digest, operator, original and replacement).
    # Survivors accepted on the ignore list are listed apart, with their
    # reason. The full, unbounded mutant data stays in the report's files
    # section; survivorsTruncated says how many more findings live only there.
    module Findings
      VERSION = 1

      # GitHub shows at most 10 annotations of one kind per step.
      LIMIT = 10

      # Published ordering, most actionable first: a coarse mutant replaces
      # the whole method body, so a surviving one says no test pins the
      # method's behavior at all. Ties break by file, line and digest, so the
      # same report always lists the same findings in the same order.
      ORDERING = "coarse survivors first, then file, line and digest"

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
            acceptedTruncated: truncated(accepted)
          }
        end

        private

        def listed(report, results)
          ordered(report, results).first(LIMIT).map { |result| finding(report, result) }
        end

        def truncated(results)
          [results.size - LIMIT, 0].max
        end

        # partition keeps the coarse group ahead; inside a group the key is
        # total (no two mutants share a digest), so the order is stable.
        def ordered(report, results)
          results.partition { |result| result.mutation.coarse }
                 .map { |group| group.sort_by { |result| tie_break(report, result) } }
                 .flatten
        end

        def tie_break(report, result)
          [path(report, result), line(result), result.digest]
        end

        def finding(report, result)
          entry = {
            digest: result.digest,
            path: path(report, result),
            line: line(result),
            endLine: end_line(result),
            subject: result.subject.id,
            operator: result.mutation.operator,
            original: joined_texts(result) { |edit| original_text(result, edit) },
            replacement: joined_texts(result, &:replacement),
            coarse: result.mutation.coarse
          }
          result.ignored ? entry.merge(reason: result.ignored) : entry
        end

        # Stryker joins a multi-edit mutant's replacements the same way, so
        # both reports describe one mutant with one text.
        def joined_texts(result, &pick)
          result.mutation.edits.map { |edit| safe_text(pick.call(edit)) }.join(" | ")
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

        def line(result)
          result.subject.line_of(result.mutation.edits.first.start_byte)
        end

        # The line the last edit's final byte sits on; an edit that ends on a
        # line boundary belongs to the line above.
        def end_line(result)
          last = result.mutation.edits.last
          result.subject.line_of([last.end_byte - 1, last.start_byte].max)
        end
      end
    end
  end
end
