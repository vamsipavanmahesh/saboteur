# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "cgi"
require "fileutils"

module Saboteur
  module Reporter
    # One self-contained HTML page: inline style, no script, no network. It is
    # rendered from the same hash the JSON reporter writes (Stryker.build), so
    # both reports list the same mutants with the same statuses. The scores can
    # differ: the JSON schema counts NoCoverage as undetected, while this page
    # shows Report#score, which leaves it out (see the "Covered mutation score"
    # label on the page). The score note says what is and is not counted.
    class Html
      STYLE = <<~CSS
        body{font:14px/1.5 system-ui,sans-serif;margin:1rem auto;max-width:72rem;padding:0 1rem;color:#1b1b1b}
        h1,h2{margin:1.2em 0 .4em}table{border-collapse:collapse;width:100%;min-width:60rem}
        th,td{border-bottom:1px solid #ddd;padding:.25rem .5rem;text-align:left;vertical-align:top;overflow-wrap:break-word}
        td.fit{white-space:nowrap}td.wide{min-width:14rem}
        th{background:#f4f4f4;font-size:12px;text-transform:uppercase}
        .scroll{overflow-x:auto}.note{color:#555;font-size:12px}
        .status{border-radius:3px;padding:0 .4rem;color:#fff;white-space:nowrap}
        .Killed{background:#2e7d32}.Survived{background:#c62828}.Timeout{background:#b45309}
        .RuntimeError{background:#6a1b9a}.NoCoverage{background:#455a64}.Ignored{background:#616161}
        .Accepted{background:#8d6e63}
        .warning{background:#fff8e1;border-left:4px solid #f9a825;margin:.3rem 0;padding:.3rem .6rem;overflow-wrap:anywhere}
        code,pre{font-family:ui-monospace,monospace;font-size:13px}
        pre{display:inline-block;vertical-align:top;margin:0;white-space:pre-wrap;overflow-wrap:anywhere}summary{cursor:pointer;font-weight:600;overflow-wrap:anywhere}
      CSS

      SCORE_FORMULA = "(killed + timeout) / (killed + survived + timeout)"

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
        names = test_names(data)
        results = report.results.to_h do |result|
          [[Stryker.relative(result.subject.file, report.root), result.digest], result]
        end
        <<~HTML
          <!DOCTYPE html>
          <html lang="en"><head><meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>saboteur report</title>
          <style>#{STYLE}</style></head><body>
          <h1>saboteur report</h1>
          #{summary(report, data)}#{warnings(data[:warnings])}#{skipped_subjects(data[:skippedSubjects])}
          <h2>Files</h2>
          #{data[:files].map { |file, entry| file_section(file, entry, names, results) }.join("\n")}
          </body></html>
        HTML
      end

      private

      def summary(report, data)
        seed = data.dig(:config, :seed)
        seed_note = seed ? ", seed #{seed}" : ""
        counts = data[:files].values.flat_map { |entry| entry[:mutants] }.map { |mutant| mutant[:status] }.tally
        <<~HTML
          <p><strong>Covered mutation score: #{score_text(report.score)}</strong>
          (#{report.subjects.size} subjects, #{report.results.size} mutants, #{format('%.1f', report.wall_time)}s#{seed_note})</p>
          <p class="note">Covered mutation score = #{SCORE_FORMULA}. NoCoverage, errors, resource limits and skipped
          mutants are not counted. Survivors accepted on the ignore list stay in the denominator. It covers only the subjects of this run, not the whole project. A tool that reads the
          Stryker JSON may show a different score, because the schema counts NoCoverage as undetected.</p>
          <p class="note">Wide tables scroll sideways.</p>
          <p>#{counts.map { |status, count| "#{status_label(status)} #{count}" }.join(' ')}</p>
          <p>Survivors: #{report.unignored_survivors.size} to fix, #{report.survivors.size - report.unignored_survivors.size}
          accepted on the ignore list (still shown as Survived, with the reason).</p>
        HTML
      end

      def score_text(score)
        score ? format("%.1f%%", score * 100) : "n/a"
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
        "<h2>Skipped subjects</h2>\n<div class=\"scroll\"><table><thead><tr><th>Subject</th><th>Location</th>" \
          "<th>Reason</th></tr></thead>#{rows.join}</table></div>"
      end

      def test_names(data)
        data[:testFiles].values.flat_map { |group| group[:tests] }.to_h { |test| [test[:id], test[:name]] }
      end

      def file_section(file, entry, names, results)
        open = entry[:mutants].any? { |mutant| mutant[:status] == "Survived" } ? " open" : ""
        ordered = entry[:mutants].sort_by { |mutant| position_key(mutant) }
        rows = ordered.map { |mutant| mutant_row(mutant, names, results[[file, mutant[:id]]]) }
        "<details#{open}><summary>#{escape(file)} (#{entry[:mutants].size} mutants)</summary>\n" \
          "<div class=\"scroll\"><table><thead><tr><th>Location</th><th>Status</th><th>Operator</th><th>Change</th>" \
          "<th>Id</th><th>Notes</th></tr></thead>\n#{rows.join("\n")}</table></div></details>"
      end

      def position_key(mutant)
        start = mutant[:location][:start]
        [start[:line], start[:column], mutant[:id]]
      end

      def mutant_row(mutant, names, result)
        start = mutant[:location][:start]
        tests = Array(mutant[:killedBy]).map { |id| names.fetch(id) }.join(", ")
        notes = [mutant[:statusReason], tests.empty? ? nil : "killed by #{tests}"].compact.join("; ")
        "<tr><td class=\"fit\">line #{start[:line]}, column #{start[:column]}</td><td>#{row_status(mutant,
                                                                                                   result)}</td>" \
          "<td>#{escape(mutant[:mutatorName])}</td><td class=\"wide\">#{change(mutant, result)}</td>" \
          "<td class=\"fit\"><code>#{escape(mutant[:id])}</code></td><td class=\"wide\">#{escape(notes)}</td></tr>"
      end

      def row_status(mutant, result)
        badge = status_label(mutant[:status])
        # Only survivors are ever put on the ignore list.
        result.ignored ? "#{badge} #{status_label('Accepted')}" : badge
      end

      # One edit shows the original text and its replacement. A mutant with
      # several edits shows only the replacements, because one location cannot
      # stand for all of them.
      def change(mutant, result)
        edits = result.mutation.edits
        return "<pre>#{escape(mutant[:replacement])}</pre>" unless edits.size == 1

        source = result.subject.file_source
        edit = edits.first
        original = source.byteslice(edit.start_byte, edit.end_byte - edit.start_byte).to_s
        "<pre>#{escape(original.dup.force_encoding(Encoding::UTF_8).scrub)}</pre> becomes " \
          "<pre>#{escape(edit.replacement)}</pre>"
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
