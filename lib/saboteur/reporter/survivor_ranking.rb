# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Review priority, not a claim that a survivor is a real defect.
    module SurvivorRanking
      ORDERING = "coarse first, then more covering tests, larger edited-line span, " \
                 "nearer changed lines, then file, line and digest"

      def self.ordered(report, results)
        results.sort_by { |result| key(report, result) }
      end

      def self.key(report, result)
        [result.mutation.coarse ? 0 : 1, -result.covered_by.uniq.size, -edited_lines(result).size,
         report.changed_line_distance(result) || Float::INFINITY,
         result.subject.file.delete_prefix("#{report.root}/"), first_line(result), result.digest]
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
