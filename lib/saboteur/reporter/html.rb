# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "cgi"
require "fileutils"

module Saboteur
  module Reporter
    # One self-contained HTML page: inline style, no script, no network. It is
    # rendered from the same hash the JSON reporter writes (Stryker.build), so
    # both reports always agree.
    class Html
      STYLE = <<~CSS
        body{font:14px/1.5 system-ui,sans-serif;margin:2rem auto;max-width:60rem;padding:0 1rem;color:#1b1b1b}
        h1,h2{margin:1.2em 0 .4em}table{border-collapse:collapse;width:100%}
        td,th{border-bottom:1px solid #ddd;padding:.25rem .5rem;text-align:left;vertical-align:top}
        .status{border-radius:3px;padding:0 .4rem;color:#fff;white-space:nowrap}
        .Killed{background:#2e7d32}.Survived{background:#c62828}.Timeout{background:#ef6c00}
        .RuntimeError{background:#6a1b9a}.NoCoverage{background:#546e7a}.Ignored{background:#757575}
        .warning{background:#fff8e1;border-left:4px solid #f9a825;margin:.3rem 0;padding:.3rem .6rem}
        code{font-family:ui-monospace,monospace}summary{cursor:pointer;font-weight:600}
      CSS

      def initialize(path)
        @path = path
      end

      def call(report)
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, self.class.build(report))
      end

      def self.build(report)
        new(nil).build(report)
      end

      def build(report)
        data = Stryker.build(report)
        <<~HTML
          <!DOCTYPE html>
          <html lang="en"><head><meta charset="utf-8"><title>saboteur report</title>
          <style>#{STYLE}</style></head><body>
          <h1>saboteur report</h1>
          #{summary(report, data)}#{warnings(data[:warnings])}#{skipped_subjects(data[:skippedSubjects])}
          <h2>Files</h2>
          #{data[:files].map { |file, entry| file_section(file, entry, test_names(data)) }.join("\n")}
          </body></html>
        HTML
      end

      private

      def summary(report, data)
        score = report.score
        seed = data.dig(:config, :seed)
        seed_note = seed ? ", seed #{seed}" : ""
        counts = data[:files].values.flat_map { |entry| entry[:mutants] }.map { |mutant| mutant[:status] }.tally
        <<~HTML
          <p><strong>Mutation score: #{score ? format('%.1f%%', score * 100) : 'n/a'}</strong>
          (#{report.subjects.size} subjects, #{report.results.size} mutants, #{format('%.1f', report.wall_time)}s#{seed_note})</p>
          <p>#{counts.map { |status, count| status_label(status) + " #{count}" }.join(' ')}</p>
        HTML
      end

      def warnings(messages)
        return "" if messages.empty?

        items = messages.map { |message| %(<div class="warning">#{escape(message)}</div>) }
        "<h2>Warnings</h2>\n#{items.join("\n")}"
      end

      def skipped_subjects(entries)
        return "" if entries.empty?

        rows = entries.map do |entry|
          "<tr><td>#{escape(entry[:subject])}</td><td>#{escape(entry[:file])}:#{entry[:line]}</td>" \
            "<td>#{escape(entry[:reason])}</td></tr>"
        end
        "<h2>Skipped subjects</h2>\n<table>#{rows.join}</table>"
      end

      def test_names(data)
        data[:testFiles].values.flat_map { |group| group[:tests] }.to_h { |test| [test[:id], test[:name]] }
      end

      def file_section(file, entry, names)
        open = entry[:mutants].any? { |mutant| mutant[:status] == "Survived" } ? " open" : ""
        ordered = entry[:mutants].sort_by { |mutant| mutant.dig(:location, :start, :line) }
        rows = ordered.map { |mutant| mutant_row(mutant, names) }
        "<details#{open}><summary>#{escape(file)} (#{entry[:mutants].size} mutants)</summary>\n" \
          "<table>#{rows.join("\n")}</table></details>"
      end

      def mutant_row(mutant, names)
        tests = Array(mutant[:killedBy]).map { |id| names.fetch(id) }.join(", ")
        detail = [mutant[:statusReason], tests.empty? ? nil : "killed by #{tests}"].compact.join("; ")
        "<tr><td>line #{mutant.dig(:location, :start, :line)}</td><td>#{status_label(mutant[:status])}</td>" \
          "<td>#{escape(mutant[:mutatorName])}</td><td><code>#{escape(mutant[:replacement])}</code></td>" \
          "<td>#{escape(detail)}</td></tr>"
      end

      def status_label(status)
        %(<span class="status #{status}">#{status}</span>)
      end

      def escape(text)
        CGI.escapeHTML(text.to_s)
      end
    end
  end
end
