# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Review priority, not a claim that a survivor is a real defect.
    module SurvivorRanking
      ORDERING = "surviving mutants per statement descending, then fewer covering tests, " \
                 "coarse first, larger edited-line span, nearer changed lines, " \
                 "then file, line and digest"

      def self.ordered(report, results)
        sizes = results.group_by { |result| statement(report, result) }.transform_values(&:size)
        results.sort_by { |result| key(report, result, sizes) }
      end

      def self.key(report, result, statement_sizes = {})
        [-statement_sizes.fetch(statement(report, result), 0), result.covered_by.uniq.size,
         result.mutation.coarse ? 0 : 1, -edited_lines(result).size,
         report.changed_line_distance(result) || Float::INFINITY,
         result.subject.file.delete_prefix("#{report.root}/"), first_line(result), result.digest]
      end

      # Statement identity: same subject at the same first mutated line.
      def self.statement(report, result)
        [result.subject.file.delete_prefix("#{report.root}/"), result.subject.id, first_line(result)]
      end

      def self.first_line(result)
        result.subject.line_of(result.mutation.edits.map(&:start_byte).min)
      end

      def self.edited_lines(result)
        result.mutation.edits.flat_map do |edit|
          first = result.subject.line_of(edit.start_byte)
          last = result.subject.line_of([edit.end_byte - 1, edit.start_byte].max)
          (first..last).to_a
        end.uniq
      end
    end
  end
end
