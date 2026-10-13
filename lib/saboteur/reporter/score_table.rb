# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../score"

module Saboteur
  module Reporter
    # One row per source file, worst score first, with survivor counts, and a
    # one-line legend for the statuses in the summary.
    class ScoreTable
      MAX_ROWS = 15
      LEGEND = ["killed: a test failed  survived: every selected test passed",
                "timeout: exceeded its deadline",
                "error, resource limit, skipped and the other statuses: not scored"].freeze

      def initialize(out, palette)
        @out = out
        @palette = palette
      end

      def call(report)
        rows = rows(report)
        return if rows.size < 2

        @out.puts "\nScore by file (worst first):"
        width = rows.first(MAX_ROWS).map { |row| row[:path].length }.max
        rows.first(MAX_ROWS).each { |row| @out.puts line(row, width) }
        @out.puts "  ... #{rows.size - MAX_ROWS} more files" if rows.size > MAX_ROWS
      end

      def legend
        LEGEND.each_with_index.map do |text, index|
          @palette.paint(:dim, "#{index.zero? ? 'legend: ' : '        '}#{text}")
        end.join("\n")
      end

      private

      def rows(report)
        by_file = report.results.group_by { |result| result.subject.file }
        rows = by_file.map { |file, results| row(report, file, results) }
        rows.reject { |row| row[:tested].zero? }.sort_by { |row| [row[:value], -row[:survivors], row[:path]] }
      end

      def row(report, file, results)
        breakdown = Score.of(results)
        { path: file.delete_prefix("#{report.root}/"), value: breakdown.value,
          survivors: results.count(&:unignored_survivor?), tested: breakdown.tested }
      end

      def line(row, width)
        score = format("%5.1f %%", row[:value] * 100)
        "  #{row[:path].ljust(width)}  #{score}  #{row[:survivors]} survivor#{'s' unless row[:survivors] == 1}"
      end
    end
  end
end
