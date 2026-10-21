# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../score"

module Saboteur
  module Reporter
    # One row per source file, worst score first, with killed/tested counts.
    #
    # The score covers tested subjects only, so a file whose subjects no
    # test covers gets no percentage: a number there would read as tested
    # and clean. The row says n/a and names the untested subjects instead,
    # and a file with both keeps its score with the untested count next to
    # it. Untested subjects are never dropped silently, even at 100 %.
    class ScoreTable
      MAX_ROWS = 15
      MAX_UNTESTED_NAMES = 3
      # The skip reason CandidateSelection gives a subject no test covers.
      NO_COVERAGE = "no coverage"

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

      private

      # Scored rows sort worst first; files with nothing tested have no
      # score to rank, so they follow, by path.
      def rows(report)
        results_by_file = report.results.group_by { |result| result.subject.file }
        untested_by_file = untested_subjects(report).group_by(&:file)
        rows = (results_by_file.keys | untested_by_file.keys).map do |file|
          row(report, file, results_by_file[file] || [], untested_by_file[file] || [])
        end
        scored, unscored = rows.partition { |row| row[:tested].positive? }
        sort_scored(scored) + unscored.reject { |row| row[:untested].empty? }.sort_by { |row| row[:path] }
      end

      def sort_scored(rows)
        rows.sort_by { |row| [row[:value], -row[:detected], row[:path]] }
      end

      def untested_subjects(report)
        report.skipped_subjects.select { |_, reason| reason == NO_COVERAGE }
              .keys.sort_by { |subject| [subject.file, subject.start_line] }
      end

      def row(report, file, results, untested)
        breakdown = Score.of(results)
        { path: file.delete_prefix("#{report.root}/"), value: breakdown.value,
          detected: breakdown.detected, tested: breakdown.tested, untested: untested }
      end

      # "cart.rb  100.0% (2/2) · n/a - 2 subjects have no tests: ...": the
      # tested score and the untested count stand next to each other; a
      # file with nothing tested gets no percentage at all.
      def line(row, width)
        note = untested_note(row[:untested])
        return "  #{row[:path].ljust(width)}  #{note}" if row[:tested].zero?

        score = format("%<value>5.1f%% (%<detected>d/%<tested>d)", **row, value: row[:value] * 100)
        base = "  #{row[:path].ljust(width)}  #{score}"
        note ? "#{base} #{@palette.glyph(:middot)} #{note}" : base
      end

      # "n/a - 2 subjects have no tests: Cart#total, Cart#biggest": names
      # the subjects the score cannot speak for, capped so a long list does
      # not swallow the row; the Not scored block lists them all.
      def untested_note(untested)
        return if untested.empty?

        names = untested.map(&:id)
        shown = names.first(MAX_UNTESTED_NAMES)
        shown << "+#{names.size - MAX_UNTESTED_NAMES} more" if names.size > MAX_UNTESTED_NAMES
        count = untested.size
        @palette.paint(:warn, "n/a - #{count} subject#{'s' unless count == 1} " \
                              "#{count == 1 ? 'has' : 'have'} no tests: #{shown.join(', ')}")
      end
    end
  end
end
