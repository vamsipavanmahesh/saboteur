# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "stringio"

require_relative "../survivor_guidance"
require_relative "../reporter/palette"
require_relative "../reporter/survivor_hints"

module Saboteur
  class CLI
    # saboteur survivors <report.json> (#475): a read-only, line-oriented
    # terminal browser for the Stryker JSON report. It never boots the
    # project or reruns tests; it lists survivors, filters them, and for
    # one digest prints the diff, the exact replay command and the
    # ignore-file template. It never edits the ignore file.
    module SurvivorsCommand
      # Where `saboteur run` writes the JSON report unless configured otherwise.
      DEFAULT_REPORT = Config::DEFAULTS["json_report"]

      # survivors owns its usage line (#1150): the report path is optional
      # because the run always writes the same default.
      SURVIVORS_USAGE = "Usage: saboteur survivors [options] [REPORT] - REPORT defaults to " \
                        ".saboteur/report.json"

      private

      def survivors_command
        survivors_command_inner
      rescue UsageError => e
        @err.puts("saboteur: #{e.message}")
        EXIT_USAGE
      end

      def survivors_command_inner
        options = {}
        parser = survivors_parser(options)
        args = parse_survivors_args(parser, options)
        if options[:help]
          @out.puts(parser)
          return EXIT_OK
        end
        path = args.shift || DEFAULT_REPORT
        raise UsageError, "unexpected arguments: #{args.join(' ')}\n#{parser}" if args.any?

        report = load_survivor_report(path)
        browser = SurvivorsBrowser.new(report, palette: Reporter::Palette.for(@out, mode: options.fetch(:color, :auto)))
        if options[:show]
          @out.puts(browser.show(options[:show]))
        else
          # Explicit keywords, and list takes no catch-all (#1267): a new
          # parser option that never reaches the browser raises here instead
          # of being swallowed. --ranked is the documented compat no-op.
          @out.puts(browser.list(file: options[:file], operator: options[:operator], triage: options[:triage]))
        end
        EXIT_OK
      end

      # The same colour flags as run (#1150), plus the browser filters.
      def survivors_parser(options)
        OptionParser.new do |opts|
          opts.banner = SURVIVORS_USAGE
          opts.on("--ranked", "Review-priority order (the default): the terminal report's ordering")
          opts.on("--file SUBSTR", "Only survivors whose path contains SUBSTR")
          opts.on("--operator NAME", "Only survivors of operator NAME")
          opts.on("--triage LABEL", "Only survivors classified LABEL (for example boundary)")
          opts.on("--show DIGEST", "Diff, replay command and ignore template for one survivor")
          opts.on("--color [MODE]", %w[always never auto],
                  "Colour the output: always, never, or auto when MODE is omitted") do |mode|
            options[:color] = (mode || :always).to_sym
          end
          opts.on("--no-color", "Alias for --color=never") { options[:color] = :never }
          opts.on("--help", "Show this help") { options[:help] = true }
        end
      end

      def parse_survivors_args(parser, options)
        parser.parse!(@argv, into: options)
      rescue OptionParser::ParseError => e
        raise UsageError, "#{e.message}\n#{parser}"
      end

      def load_survivor_report(path)
        unless File.file?(path)
          hint = path == DEFAULT_REPORT ? "; run saboteur first, or pass a report path" : ""
          raise UsageError, "report not found: #{path}#{hint}"
        end

        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise UsageError, "#{path} is not a readable saboteur report: #{e.message}"
      end
    end

    # Reads the report's files section (the complete mutant list), not the
    # capped findings, so survivors beyond the findings limit still list.
    class SurvivorsBrowser
      # Sibling digests named on a collapse line; the rest are a count - the
      # same shape the terminal report's collapse uses (#1150).
      SIBLING_DIGEST_CAP = 3

      def initialize(report, palette: Reporter::Palette.for(StringIO.new))
        @report = report
        @findings = report.dig("saboteur", "findings") || {}
        @palette = palette
      end

      # One ordering everywhere (#1150): the terminal report's ranked order
      # is the default, exactly as the findings carry it; --ranked stays
      # accepted for compatibility.
      def list(file: nil, operator: nil, triage: nil)
        survivors = ranked_order(filtered(file, operator, triage))
        return "no survivors#{filters_note(file, operator, triage)}" if survivors.empty?

        [header(survivors.size, file, operator, triage), *rows(survivors)]
      end

      def show(digest)
        survivor = unique_survivor(digest)
        finding = findings_by_digest[survivor[:digest]] || {}
        subject = finding["subject"] || survivor[:subject]
        seed = @report.dig("config", "seed")
        [
          *detail_lines(survivor, finding),
          "",
          "replay one survivor: #{SurvivorGuidance.replay_command(survivor[:digest], seed: seed)}",
          "  #{SurvivorGuidance::REPLAY_CAVEAT}",
          "",
          SurvivorGuidance::IGNORE_INTRO,
          "  #{SurvivorGuidance::IGNORE_CONFIG}",
          "  #{ignore_entry(survivor, subject)}"
        ].join("\n")
      end

      private

      def detail_lines(survivor, finding)
        [
          "#{survivor[:path]}:#{survivor[:line]}  #{survivor[:operator]}  #{survivor[:digest]}",
          *classification_line(survivor[:classification]),
          "",
          "- #{finding['original'] || original_line(survivor)}",
          "+ #{finding['replacement'] || survivor[:replacement]}",
          "why it matters: #{Reporter::SurvivorHints.why(survivor[:operator])}",
          *covered_line(survivor),
          *hint_line(survivor, survivor[:classification])
        ]
      end

      # The same wording the terminal survivor block uses (#1183).
      def classification_line(label)
        return [] unless label

        reason = Reporter::SurvivorHints.label_reason(label)
        ["classification: #{label}#{" - #{reason}" if reason}"]
      end

      def covered_line(survivor)
        names = survivor[:covered].map { |id| test_names[id] }.compact
        return [] if names.empty?

        rest = " (+#{names.size - 1} more)" if names.size >= 2
        ["covered by #{names.first}#{rest} - ran, still passed"]
      end

      def test_names
        @test_names ||= @report.fetch("testFiles", {}).values
                               .flat_map { |file| file.fetch("tests", []) }
                               .to_h { |test| [test["id"], test["name"]] }
      end

      def hint_line(survivor, label)
        return [] unless label

        text = Reporter::SurvivorHints.for_label(survivor[:operator], label: label)
        text ? ["hint: #{text}"] : []
      end

      # A prefix names one survivor or none: an ambiguous one is refused
      # with the candidates, never resolved to the first match.
      def unique_survivor(digest)
        match, *others = all_survivors.select { |s| s[:digest].start_with?(digest) }
        raise UsageError, "no survivor with digest #{digest} in this report" unless match
        return match if others.empty?

        digests = [match, *others].map { |m| m[:digest] }.sort
        raise UsageError, "digest prefix #{digest} matches #{digests.size} survivors: " \
                          "#{digests.join(', ')}; use more characters"
      end

      def filtered(file, operator, triage)
        survivors = all_survivors
        survivors = survivors.select { |s| s[:path].include?(file) } if file
        survivors = survivors.select { |s| s[:operator] == operator } if operator
        triage ? survivors.select { |s| s[:classification] == triage } : survivors
      end

      def header(size, file, operator, triage)
        text = "#{size} survivor#{'s' unless size == 1}#{filters_note(file, operator, triage)}"
        truncated = @findings["survivorsTruncated"].to_i
        if truncated.positive?
          text = "#{text} (the report's ranked findings name only the first #{@findings['limit'] || 10})"
        end
        @palette.paint(:head, text)
      end

      # The terminal collapse: sibling mutants on one statement fold into the
      # first row, which names up to SIBLING_DIGEST_CAP of their digests.
      def rows(survivors)
        survivors.group_by { |s| [s[:path], s[:line]] }.values.each_with_index.map do |group, i|
          first, *siblings = group
          format("%3<i>d. %<path>s:%<line>d  %-28<operator>s %<digest>s  %<classification>s%<suffix>s",
                 i: i + 1, path: first[:path], line: first[:line], operator: first[:operator],
                 digest: first[:digest], classification: first[:classification] || "-",
                 suffix: siblings_suffix(siblings))
        end
      end

      def siblings_suffix(siblings)
        return "" if siblings.empty?

        named = siblings.first(SIBLING_DIGEST_CAP).map { |s| s[:digest] }.join(", ")
        rest = siblings.size - SIBLING_DIGEST_CAP
        "  (+#{siblings.size} here: #{named}#{", +#{rest} more" if rest.positive?})"
      end

      def ignore_entry(survivor, subject)
        block = if subject
                  SurvivorGuidance.ignore_block(survivor[:digest], subject)
                else
                  SurvivorGuidance.ignore_block(survivor[:digest], "Klass#meth",
                                                todo: "capped findings omit this digest - fill in the subject")
                end
        block.gsub("\n", "\n  ")
      end

      def all_survivors
        @all_survivors ||= begin
          survivors = @report.fetch("files", {}).flat_map do |path, entry|
            entry.fetch("mutants", []).select { |m| m["status"] == "Survived" }.map do |m|
              { path: path, line: m.dig("location", "start", "line").to_i, operator: m["mutatorName"],
                digest: m["id"], replacement: m["replacement"], classification: m["classification"],
                subject: m["subject"], covered: m["coveredBy"] || [], source: entry["source"] }
            end
          end
          survivors
        end
      end

      # Ranked order straight from the report: the uncapped findings "order"
      # list first, with the capped findings as the fallback for older
      # reports; anything unknown trails in file order.
      def ranked_order(survivors)
        order = @findings["order"] ||
                (@findings.fetch("survivors", []) + @findings.fetch("accepted", [])).map { |f| f["digest"] }
        rank = order.each_with_index.to_h
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
