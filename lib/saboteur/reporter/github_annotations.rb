# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "findings"
require_relative "score_table"

module Saboteur
  module Reporter
    # GitHub Actions workflow commands for a finished run: one ::error per
    # unignored survivor and one ::warning per untested subject, each on the
    # file and line of the current tree, so the findings land on the
    # pull-request diff. Survivors accepted on the ignore list never
    # annotate. The CLI auto-detects GitHub Actions; the text report and the
    # exit code are unchanged.
    class GithubAnnotations
      # A workflow command cannot carry these bytes raw, in a property value
      # or in the message data.
      # Two contexts, per the workflow-command grammar and the action's
      # escape_property/escape_data pair (action/run-saboteur): property
      # values (file, line, title) also escape ':' and ',', which terminate
      # a property; the message data after '::' escapes only %, CR and LF
      # (#1165).
      DATA_ESCAPES = { "%" => "%25", "\r" => "%0D", "\n" => "%0A" }.freeze

      # C3/C4 splits the untested-subject reason into NO_TESTS ("no
      # tests", a dark file) and NO_COVERAGE; both annotate. This slice
      # lands after them in the train but its base has no NO_TESTS
      # constant yet, so it compares the reason text.
      UNTESTED_REASONS = ["no coverage", "no tests"].freeze
      PROPERTY_ESCAPES = DATA_ESCAPES.merge(":" => "%3A", "," => "%2C").freeze

      def initialize(out, replay_command:)
        @out = out
        @replay_command = replay_command
      end

      def call(report)
        Findings.build(report)[:survivors].each { |finding| @out.puts(error_line(finding)) }
        untested_subjects(report).each { |subject| @out.puts(warning_line(report, subject)) }
      end

      private

      def error_line(finding)
        message = "#{finding[:original]} -> #{finding[:replacement]} · spec still passed. " \
                  "Replay: #{@replay_command.call(finding[:digest])}"
        "::error file=#{escape_property(finding[:path])},line=#{finding[:line]}," \
          "title=#{escape_property("survived mutant (#{finding[:operator]})")}::#{escape_data(message)}"
      end

      def warning_line(report, subject)
        path = subject.file.delete_prefix("#{report.root}/")
        "::warning file=#{escape_property(path)},line=#{subject.start_line}," \
          "title=subject has no tests::#{escape_data("#{subject.id} is not exercised by any spec")}"
      end

      def untested_subjects(report)
        report.skipped_subjects.select { |_, reason| UNTESTED_REASONS.include?(reason) }.keys
      end

      def escape_data(text)
        text.to_s.gsub(/[%\r\n]/, DATA_ESCAPES)
      end

      def escape_property(text)
        text.to_s.gsub(/[%\r\n:,]/, PROPERTY_ESCAPES)
      end
    end
  end
end
