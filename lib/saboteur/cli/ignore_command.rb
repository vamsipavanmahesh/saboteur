# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require_relative "../ignore_ratchet"

module Saboteur
  class CLI
    # saboteur ignore --check / --prune (plan-PR 15): the ignore ratchet.
    # Read-only against the project; --prune edits only the ignore file.
    module IgnoreCommand
      private

      def ignore_command
        ignore_command_inner
      rescue UsageError => e
        @err.puts("saboteur: #{e.message}")
        EXIT_USAGE
      end

      def ignore_command_inner
        options = ignore_options
        raise UsageError, "no report at #{config['json_report']} - run a full saboteur run first" unless report_exist?

        report = JSON.parse(File.read(config.path("json_report")))
        ratchet = IgnoreRatchet.new(ignore_text: ignore_text, report:)
        palette = Reporter::Palette.for(@out, overrides: config["palette"])
        options[:prune] ? ignore_prune(ratchet, palette) : ignore_check(ratchet, palette)
      rescue JSON::ParserError => e
        raise UsageError, "#{config['json_report']} is not a readable saboteur report: #{e.message}"
      end

      def ignore_options
        options = {}
        parser = OptionParser.new do |opts|
          opts.on("--check", "List stale ignore entries; exit 1 when any exist")
          opts.on("--prune", "Delete the stale entries and list what was removed")
        end
        args = parser.parse!(@argv, into: options)
        raise UsageError, "unexpected arguments: #{args.join(' ')}" if args.any?

        unless options.key?(:check) ^ options.key?(:prune)
          raise UsageError, "choose one: saboteur ignore --check or saboteur ignore --prune"
        end

        options
      end

      def ignore_check(ratchet, palette)
        stale = ratchet.verdicts.select(&:stale?)
        return ignore_check_clean(ratchet, palette) if stale.empty?

        @out.puts "#{palette.paint(:head, 'ignore ratchet:')} #{stale.size} stale " \
                  "#{ignore_plural(stale.size)} in #{config['ignore_file']}"
        stale.each { |verdict| @out.puts ignore_verdict_line(verdict, palette) }
        @out.puts "  #{palette.paint(:info, palette.glyph(:arrow))} prune: saboteur ignore --prune"
        @out.puts palette.paint(:fail, "exit 1 - #{stale.size} stale ignore #{ignore_plural(stale.size)}")
        EXIT_SURVIVORS
      end

      def ignore_check_clean(ratchet, palette)
        if (reason = ratchet.undecidable_reason)
          message = "nothing decided for #{config['ignore_file']} - #{reason}"
          @out.puts "#{palette.paint(:head, 'ignore ratchet:')} #{message}"
          ratchet.verdicts.each { |verdict| @out.puts ignore_verdict_line(verdict, palette) }
        else
          count = ratchet.verdicts.size
          @out.puts "ignore ratchet: #{config['ignore_file']} is clean (#{count} #{ignore_plural(count)} checked)"
        end
        EXIT_OK
      end

      def ignore_prune(ratchet, palette)
        stale = ratchet.verdicts.select(&:stale?)
        if stale.empty?
          @out.puts "ignore ratchet: nothing to prune in #{config['ignore_file']}"
          return EXIT_OK
        end

        File.write(config.path("ignore_file"), ratchet.pruned_text(File.read(config.path("ignore_file"))))
        @out.puts "#{palette.paint(:head, 'ignore ratchet:')} pruned #{stale.size} stale " \
                  "#{ignore_plural(stale.size)} from #{config['ignore_file']}"
        stale.each { |verdict| @out.puts ignore_verdict_line(verdict, palette) }
        EXIT_OK
      end

      def ignore_verdict_line(verdict, palette)
        entry = verdict.entry
        digest = entry.digest ? "#{entry.digest[0, 6]}..." : "(unparsed entry)"
        "  #{palette.paint(:warn, digest)} #{entry.subject || '(unknown subject)'} - #{verdict.note}"
      end

      def ignore_text
        path = config.path("ignore_file")
        path && File.file?(path) ? File.read(path) : ""
      end

      def report_exist? = File.file?(config.path("json_report").to_s)

      def ignore_plural(size) = size == 1 ? "entry" : "entries"
    end
  end
end
