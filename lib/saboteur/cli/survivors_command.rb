# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"

require_relative "../survivor_guidance"

module Saboteur
  class CLI
    # saboteur survivors <report.json> (#475): a read-only, line-oriented
    # terminal browser for the Stryker JSON report. It never boots the
    # project or reruns tests; it lists survivors, filters them, and for
    # one digest prints the diff, the exact replay command and the
    # ignore-file template. It never edits the ignore file.
    module SurvivorsCommand
      private

      def survivors_command
        survivors_command_inner
      rescue UsageError => e
        @err.puts("saboteur: #{e.message}")
        EXIT_USAGE
      end

      def survivors_command_inner
        parser = OptionParser.new do |opts|
          opts.on("--ranked", "Review-priority order: the report's ranked findings first")
          opts.on("--file SUBSTR", "Only survivors whose path contains SUBSTR")
          opts.on("--operator NAME", "Only survivors of operator NAME")
          opts.on("--triage LABEL", "Only survivors classified LABEL (for example missing_test)")
          opts.on("--show DIGEST", "Diff, replay command and ignore template for one survivor")
        end
        options = {}
        args = parser.parse!(@argv, into: options)
        path = args.shift or raise UsageError,
                                   "survivors expects a report path: saboteur survivors .saboteur/report.json"
        raise UsageError, "unexpected arguments: #{args.join(' ')}" if args.any?

        report = load_survivor_report(path)
        browser = SurvivorsBrowser.new(report)
        if options[:show]
          @out.puts(browser.show(options[:show]))
        else
          @out.puts(browser.list(**options.slice(:ranked, :file, :operator, :triage)))
        end
        EXIT_OK
      end

      def load_survivor_report(path)
        raise UsageError, "report not found: #{path}" unless File.file?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise UsageError, "#{path} is not a readable saboteur report: #{e.message}"
      end
    end

    # Reads the report's files section (the complete mutant list), not the
    # capped findings, so survivors beyond the findings limit still list.
    class SurvivorsBrowser
      def initialize(report)
        @report = report
        @findings = report.dig("saboteur", "findings") || {}
      end

      def list(ranked: false, file: nil, operator: nil, triage: nil)
        survivors = filtered(file, operator, triage)
        survivors = ranked_order(survivors) if ranked
        return "no survivors#{filters_note(file, operator, triage)}" if survivors.empty?

        [header(survivors.size, file, operator, triage), *rows(survivors)]
      end

      def show(digest)
        survivor = all_survivors.find { |s| s[:digest].start_with?(digest) } ||
                   raise(UsageError, "no survivor with digest #{digest} in this report")
        finding = findings_by_digest[survivor[:digest]] || {}
        subject = finding["subject"]
        seed = @report.dig("config", "seed")
        [
          "#{survivor[:path]}:#{survivor[:line]}  #{survivor[:operator]}  #{survivor[:digest]}",
          "",
          "- #{finding['original'] || original_line(survivor)}",
          "+ #{finding['replacement'] || survivor[:replacement]}",
          "",
          "replay one survivor: #{SurvivorGuidance.replay_command(survivor[:digest], seed: seed)}",
          "  #{SurvivorGuidance::REPLAY_CAVEAT}",
          "",
          SurvivorGuidance::IGNORE_INTRO,
          "  #{ignore_entry(survivor, subject)}"
        ].join("\n")
      end

      private

      def filtered(file, operator, triage)
        survivors = all_survivors
        survivors = survivors.select { |s| s[:path].include?(file) } if file
        survivors = survivors.select { |s| s[:operator] == operator } if operator
        triage ? survivors.select { |s| s[:classification] == triage } : survivors
      end

      def header(size, file, operator, triage)
        text = "#{size} survivor#{'s' unless size == 1}#{filters_note(file, operator, triage)}"
        truncated = @findings["survivorsTruncated"].to_i
        return text unless truncated.positive?

        "#{text} (the report's ranked findings name only the first #{@findings['limit'] || 10})"
      end

      def rows(survivors)
        survivors.each_with_index.map do |s, i|
          format("%3<i>d. %<path>s:%<line>d  %-28<operator>s %<digest>s  %<classification>s",
                 i: i + 1, path: s[:path], line: s[:line], operator: s[:operator], digest: s[:digest],
                 classification: s[:classification] || "-")
        end
      end

      def ignore_entry(survivor, subject)
        return SurvivorGuidance.ignore_entry(survivor[:digest], subject) if subject

        SurvivorGuidance.ignore_entry(survivor[:digest], "Klass#meth",
                                      todo: "capped findings omit this digest - fill in the subject")
      end

      def all_survivors
        @all_survivors ||= begin
          survivors = @report.fetch("files", {}).flat_map do |path, entry|
            entry.fetch("mutants", []).select { |m| m["status"] == "Survived" }.map do |m|
              { path: path, line: m.dig("location", "start", "line").to_i, operator: m["mutatorName"],
                digest: m["id"], replacement: m["replacement"], classification: m["classification"],
                covered: m["coveredBy"] || [], source: entry["source"] }
            end
          end
          survivors.sort_by { |s| [s[:path], s[:line], s[:digest]] }
        end
      end

      def ranked_order(survivors)
        rank = @findings.fetch("survivors", []).each_with_index.to_h { |f, i| [f["digest"], i] }
        survivors.sort_by { |s| [rank[s[:digest]] || Float::INFINITY, -s[:covered].size, s[:path], s[:line], s[:digest]] }
      end

      def findings_by_digest
        @findings_by_digest ||=
          (@findings.fetch("survivors", []) + @findings.fetch("accepted", [])).to_h { |f| [f["digest"], f] }
      end

      def original_line(survivor)
        survivor[:source].to_s.lines[survivor[:line] - 1].to_s.strip
      end

      def filters_note(file, operator, triage)
        parts = []
        parts << "file~#{file}" if file
        parts << "operator=#{operator}" if operator
        parts << "triage=#{triage}" if triage
        parts.empty? ? "" : " (#{parts.join(', ')})"
      end
    end
  end
end
