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

      # Published ordering, coarse survivors first: a surviving coarse mutant
      # replaced the whole method body, which hints that no test pins the
      # method's behavior - though it can also be a re-evaluation limit or an
      # equivalent mutant, so this is a heuristic, not a guarantee. Ties break
      # by file, line and digest, so one report always reads the same way.
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
            edits: edit_entries(result),
            coarse: result.mutation.coarse
          }
          result.ignored ? entry.merge(reason: result.ignored) : entry
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

        def line(result)
          result.subject.line_of(result.mutation.edits.map(&:start_byte).min)
        end

        # The line the last edit's final byte sits on; an edit that ends on a
        # line boundary belongs to the line above. The range spans every edit,
        # wherever the mutation source ordered them.
        def end_line(result)
          edits = result.mutation.edits
          last_byte = edits.map(&:end_byte).max - 1
          first_byte = edits.map(&:start_byte).min
          result.subject.line_of([last_byte, first_byte].max)
        end
      end
    end
  end
end
