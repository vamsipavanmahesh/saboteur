# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "cgi"
require "fileutils"

require_relative "../survivor_guidance"
require_relative "survivor_classification"

module Saboteur
  module Reporter
    # One self-contained HTML page: inline style and script, no network. The
    # body is the mutation-testing-elements viewer (the vendored UMD bundle
    # under assets/, pinned there by version and sha256) with the Stryker
    # report JSON inlined, so the page works from file://. Viewer and table
    # are rendered from the same hash the JSON reporter writes (Stryker.build),
    # so both list the same mutants with the same statuses. The scores can
    # differ: the JSON schema counts NoCoverage as undetected, while this page
    # shows Report#score, which leaves it out (see the "Covered mutation
    # score" label on the page). The score note says what is and is not counted.
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
        .Accepted,.Triage_accepted_equivalent{background:#8d6e63}
        .Triage_wont_fix{background:#616161}.Triage_todo{background:#b45309}
        .classification{border-radius:3px;padding:0 .4rem;background:#eceff1;color:#37474f;white-space:nowrap}
        .copy{font-size:11px;padding:0 .3rem;margin-left:.3rem;cursor:pointer}
        .warning{background:#fff8e1;border-left:4px solid #f9a825;margin:.3rem 0;padding:.3rem .6rem;overflow-wrap:anywhere}
        code,pre{font-family:ui-monospace,monospace;font-size:13px}
        pre{display:inline-block;vertical-align:top;margin:0;white-space:pre-wrap;overflow-wrap:anywhere}summary{cursor:pointer;font-weight:600;overflow-wrap:anywhere}
        /* Paper cannot scroll sideways, and the dark viewer is screen-only
           ink: print the table, not the widget, and let wide tables wrap. */
        @media print{
          mutation-test-report-app{display:none}
          .copy,.print-hide{display:none}
          details::details-content{content-visibility:visible}
          body{max-width:none}
          table{min-width:0}
          .scroll{overflow-x:visible}
        }
      CSS

      SCORE_FORMULA = "(killed + timeout) / (killed + survived + timeout)"

      # A survivor-bearing file section opens on load - but only the first
      # OPEN_FILE_LIMIT of them, and only while the open rows stay under
      # OPEN_ROW_BUDGET, so a big run does not land as a wall of expanded
      # rows. The rest stay collapsed with their survivor count in the header.
      OPEN_FILE_LIMIT = 10
      OPEN_ROW_BUDGET = 30
      # Survivor rows get a copy button for the replay command. file:// is a
      # secure context, so navigator.clipboard works; the textarea fallback
      # covers browsers where it rejects without a gesture. One delegated
      # listener keeps the page free of per-row scripts.
      COPY_SCRIPT = <<~JS
        document.addEventListener("click",function(event){
        var button=event.target.closest("button.copy");if(!button)return;
        var text=button.getAttribute("data-copy");
        function done(){button.textContent="copied";setTimeout(function(){button.textContent="copy"},1200)}
        function fallback(){var area=document.createElement("textarea");area.value=text;
        document.body.appendChild(area);area.select();try{document.execCommand("copy")}catch(e){}
        document.body.removeChild(area);done()}
        if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(text).then(done,fallback)}
        else{fallback()}})
      JS

      # Fallback for engines without details::details-content (the print CSS
      # does this JS-free where supported): open every details for the
      # printout, then restore the reader's open/closed state afterwards.
      PRINT_SCRIPT = <<~JS
        (function(){var wasClosed=[];
        window.addEventListener("beforeprint",function(){wasClosed=[];
        document.querySelectorAll("details:not([open])").forEach(function(d){wasClosed.push(d);d.open=true})});
        window.addEventListener("afterprint",function(){wasClosed.forEach(function(d){d.open=false});wasClosed=[]})})();
      JS

      # The vendored viewer bundle, embedded verbatim into every report.
      BUNDLE_PATH = File.expand_path("assets/mutation_report.js", __dir__)

      # binread + force: the bundle is UTF-8; the default external encoding
      # depends on the locale of the shell that ran saboteur.
      def bundle
        File.binread(BUNDLE_PATH).force_encoding(Encoding::UTF_8)
      end

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
        sections, collapsed = file_sections(data, names, results, report)
        <<~HTML
          <!DOCTYPE html>
          <html lang="en"><head><meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>saboteur report</title>
          <style>#{STYLE}</style>
          <script>#{bundle}</script></head><body>
          <h1>saboteur report</h1>
          #{headline(report)}
          #{scope_note(report)}
          <mutation-test-report-app theme="dark" title-postfix="saboteur"></mutation-test-report-app>
          <script type="application/json" id="saboteur-report-json">#{embed_json(data)}</script>
          <script>document.querySelector("mutation-test-report-app").report =
          JSON.parse(document.getElementById("saboteur-report-json").textContent);
          #{COPY_SCRIPT}#{PRINT_SCRIPT}</script>
          <details><summary>How the score is computed</summary>
          #{summary(report, data)}
          </details>
          #{inline_suppressions(report)}#{warnings(data[:warnings])}#{skipped_subjects(data[:skippedSubjects])}
          <h2>Files</h2>
          <p class="note">The viewer above and this table list the same mutants; the table adds notes,
          covering tests and triage reasons.</p>
          #{collapse_note(collapsed)}#{file_listing(sections)}
          </body></html>
        HTML
      end

      private

      # The honest pair (#3): the score over tested subjects and, when the
      # run skipped subjects for want of tests, the count it cannot see -
      # the same contract as the terminal headline.
      def headline(report)
        breakdown = report.score_breakdown
        text = "<p><strong>Covered mutation score: #{score_text(report.score)}</strong>"
        text << " (#{breakdown.detected}/#{breakdown.tested} killed, tested subjects)" if breakdown.tested.positive?
        untested = report.skipped_subjects.count { |_, reason| reason == ScoreTable::NO_COVERAGE }
        if untested.positive?
          noun = untested == 1 ? "subject" : "subjects"
          text << " - #{untested} #{noun} not scored - no tests exist"
        end
        "#{text}</p>"
      end

      # Inline JSON for the viewer: escape every "<" so hostile source text
      # (a file name or reason holding "<script>" or "</script>") stays inert
      # inside the tag. JSON.parse turns "<" back into "<".
      def embed_json(data)
        JSON.generate(data).gsub("<", '\u003c')
      end

      def inline_suppressions(report)
        return "" if report.inline_suppressions.empty?

        items = report.inline_suppressions.map do |entry|
          path = entry[:file].delete_prefix("#{report.root}/")
          "<li>#{escape(path)}:#{entry[:line]} #{escape(entry[:subject])} " \
            "#{escape(entry[:operator])} <code>#{escape(entry[:digest])}</code>: #{escape(entry[:reason])}</li>"
        end
        "<h2>Inline suppressions (#{items.size}, outside the score)</h2><ul>#{items.join}</ul>"
      end

      # A diff run's score covers only the changed lines; the shareable
      # page says so, or a reader takes it for the whole project.
      def scope_note(report)
        return "" unless report.diff? && report.since

        "<p class=\"note\">Diff run: only lines changed since #{escape(report.since)} are mutated - " \
          "the score covers those changes, not the whole project.</p>"
      end

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
          #{score_split(report)}
          <p class="note">Wide tables scroll sideways.</p>
          <p>#{counts.map { |status, count| "#{status_label(status)} #{count}" }.join(' ')}</p>
          <p>Survivors: #{report.unignored_survivors.size} to fix, #{report.survivors.size - report.unignored_survivors.size}
          accepted on the ignore list (still shown as Survived, with the reason).</p>
        HTML
      end

      # How the score splits into assertion and crash kills, and the score
      # without the whole-body mutants, which almost any test that runs the
      # method kills. Each part shows only when it has something to say.
      def score_split(report)
        breakdown = report.score_breakdown
        lines = []
        lines << kill_split_line(breakdown) if breakdown.split_known?
        lines << whole_body_line(report)
        lines.compact.join("\n")
      end

      def kill_split_line(breakdown)
        "<p>Of the tested mutants: #{parts_text(breakdown)}. A crash shows the code ran and broke, " \
          "not that a test checked a value.</p>"
      end

      def parts_text(breakdown)
        breakdown.parts.map { |label, share| "#{score_text(share)} #{label}" }.join(", ")
      end

      def whole_body_line(report)
        whole = report.coarse_score_breakdown
        fine = report.fine_score_breakdown
        return if whole.tested.zero? || fine.tested.zero?

        split = fine.split_known? ? " (#{parts_text(fine)})" : ""
        "<p>Without whole-body mutants (body_nil, body_true, body_false, body_raise): #{score_text(fine.value)}" \
          "#{split} over #{fine.tested} mutants. Whole-body mutants alone: #{score_text(whole.value)} " \
          "over #{whole.tested}.</p>"
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

      # The sections in page order; the open set is the top survivor-bearing
      # files by survivor count, within the row budget. Returns the rendered
      # sections and the count of survivor-bearing files left collapsed.
      def file_sections(data, names, results, report)
        survivors = data[:files].to_h do |file, entry|
          [file, entry[:mutants].count { |mutant| mutant[:status] == "Survived" }]
        end
        open_set = open_files(data, survivors)
        collapsed = data[:files].keys.count { |file| survivors[file].positive? && !open_set[file] }
        sections = data[:files].map do |file, entry|
          file_section(file, entry, names, results, report, survivor_count: survivors[file], open_file: open_set[file])
        end
        [sections, collapsed]
      end

      # The open set: the top survivor-bearing files by survivor count, while
      # the open rows stay under the budget.
      def open_files(data, survivors)
        ranked = data[:files].keys.select { |file| survivors[file].positive? }
                             .sort_by { |file| [-survivors[file], file] }
        open_set = {}
        rows = 0
        ranked.first(OPEN_FILE_LIMIT).each do |file|
          break if rows >= OPEN_ROW_BUDGET

          open_set[file] = true
          rows += data[:files].fetch(file)[:mutants].size
        end
        open_set
      end

      def collapse_note(collapsed)
        noun = collapsed == 1 ? "file" : "files"
        if collapsed.zero?
          ""
        else
          "<p class=\"note print-hide\" id=\"files\">#{collapsed} #{noun} with survivors collapsed - " \
            "<a href=\"#files\" onclick=\"document.querySelectorAll('details.file').forEach" \
            "(function(d){d.open=true});return false\">expand all</a></p>\n"
        end
      end

      def file_section(file, entry, names, results, report, survivor_count:, open_file:)
        open = open_file ? " open" : ""
        ordered = entry[:mutants].sort_by { |mutant| position_key(mutant) }
        rows = ordered.map { |mutant| mutant_row(mutant, names, results[[file, mutant[:id]]], report) }
        "<details class=\"file\"#{open}><summary>#{escape(file)} " \
          "(#{entry[:mutants].size} mutants#{survivors_note(survivor_count, open_file)})</summary>\n" \
          "<div class=\"scroll\"><table><thead><tr><th>Location</th><th>Status</th><th>Operator</th><th>Change</th>" \
          "<th>Id</th><th>Notes</th></tr></thead>\n#{rows.join("\n")}</table></div></details>"
      end

      # A collapsed survivor file names its survivors in the header, so the
      # count is visible without expanding it.
      def file_listing(sections)
        return sections.join("\n") unless sections.empty?

        "<p class=\"note\">No mutants - nothing to show.</p>"
      end

      def survivors_note(survivor_count, open_file)
        open_file || survivor_count.zero? ? "" : ", #{survivor_count} survivor#{'s' unless survivor_count == 1}"
      end

      def position_key(mutant)
        start = mutant[:location][:start]
        [start[:line], start[:column], mutant[:id]]
      end

      def mutant_row(mutant, names, result, report)
        tests = Array(mutant[:killedBy]).map { |id| names.fetch(id) }.join(", ")
        notes = [mutant[:statusReason], tests.empty? ? nil : "killed by #{tests}",
                 passing_tests_note(mutant, names, result)].compact.join("; ")
        "<tr><td class=\"fit\">#{location_cell(mutant[:location][:start], result, report)}</td>" \
          "<td>#{row_status(mutant, result)}</td>" \
          "<td>#{escape(mutant[:mutatorName])}</td><td class=\"wide\">#{change(mutant, result)}</td>" \
          "<td class=\"fit\"><code>#{escape(mutant[:id])}</code>#{copy_button(mutant, seed: report.seed)}</td>" \
          "<td class=\"wide\">#{escape(notes)}</td></tr>"
      end

      # In diff mode, the changed lines the mutant touches, under its own
      # location: the mutated statement can start a line or two above the
      # changed line, so the first line alone can point at the wrong place.
      def location_cell(start, result, report)
        cell = "line #{start[:line]}, column #{start[:column]}"
        lines = report.changed_lines_for(result)
        return cell if lines.empty?

        "#{cell}<br>changed #{lines.one? ? 'line' : 'lines'} #{lines.join(', ')}"
      end

      # A survivor's covering tests all passed with the mutant applied, or, for
      # a reused verdict, in the earlier run it came from.
      def passing_tests_note(mutant, names, result)
        return unless mutant[:status] == "Survived"

        passed = Array(mutant[:coveredBy]).map { |id| names.fetch(id) }
        return if passed.empty?

        shown = passed.first(Terminal::MAX_PASSING_TESTS).join(", ")
        more = passed.size - Terminal::MAX_PASSING_TESTS
        extra = more.positive? ? " (+#{more} more)" : ""
        when_passed = result.reused? ? "passed in an earlier run" : "passed"
        "covered by #{passed.size} #{passed.one? ? 'test' : 'tests'} that #{when_passed}: #{shown}#{extra}"
      end

      # Only survivors are worth replaying, so only they get the button.
      # Every row's button reads "copy"; the aria-label names the mutant it
      # belongs to, so a screen reader's button list stays navigable.
      def copy_button(mutant, seed: nil)
        return unless mutant[:status] == "Survived"

        replay = escape(SurvivorGuidance.replay_command(mutant[:id], seed: seed))
        start = mutant[:location][:start]
        label = escape("Copy the replay command for #{mutant[:mutatorName]} " \
                       "at line #{start[:line]}, column #{start[:column]}")
        "<button type=\"button\" class=\"copy\" data-copy=\"#{replay}\" aria-label=\"#{label}\" " \
          'title="Copy the replay command">copy</button>'
      end

      def row_status(mutant, result)
        badge = status_label(mutant[:status])
        # Only survivors are ever put on the ignore list.
        if result.ignored || result.triage_state
          # An entry without a state predates triage states: render Accepted.
          badge = if result.triage_state.nil?
                    "#{badge} #{status_label('Accepted')}"
                  else
                    "#{badge} #{status_label(triage_badge(result), css_class: "Triage_#{result.triage_state}")}"
                  end
        end
        # The survivor's classification, as a label only (#192).
        label = SurvivorClassification.label(result)
        label ? "#{badge} <span class=\"classification\">#{escape(label)}</span>" : badge
      end

      # One edit shows the original text and its replacement. A mutant with
      # several edits shows only the replacements, because one location cannot
      # stand for all of them.
      def triage_badge(result)
        case result.triage_state
        when "wont_fix" then "Won\u2019t fix"
        when "todo" then "Todo"
        else "Accepted"
        end
      end

      def change(mutant, result)
        edits = result.mutation.edits
        return "<pre>#{escape(mutant[:replacement])}</pre>" unless edits.size == 1

        source = result.subject.file_source
        edit = edits.first
        original = source.byteslice(edit.start_byte, edit.end_byte - edit.start_byte).to_s
        "<pre>#{escape(original.dup.force_encoding(Encoding::UTF_8).scrub)}</pre> becomes " \
          "<pre>#{escape(edit.replacement)}</pre>"
      end

      def status_label(status, css_class: status)
        %(<span class="status #{css_class}">#{status}</span>)
      end

      def escape(text)
        CGI.escapeHTML(text.to_s)
      end
    end
  end
end
