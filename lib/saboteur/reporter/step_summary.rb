# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "findings"
require_relative "score_table"
require_relative "../score"

module Saboteur
  module Reporter
    # The GitHub step summary (PR12): a markdown per-file score table (the
    # tested-subject score pair and the untested subjects, named) plus the
    # surviving mutants with their digests. Appended to $GITHUB_STEP_SUMMARY
    # when the variable is set, never truncating what a prior step wrote;
    # a no-op everywhere else. Survivors accepted
    # on the ignore list stay out, as they do in the annotations.
    class StepSummary
      def initialize(env: ENV)
        @path = env["GITHUB_STEP_SUMMARY"]
      end

      def call(report)
        return unless @path

        File.write(@path, markdown(report), mode: "a")
      end

      private

      def markdown(report)
        lines = ["## Saboteur mutation report", "",
                 "| File | Score (tested subjects) | Untested subjects |",
                 "| --- | --- | --- |",
                 *rows(report)]
        findings = Findings.build(report)[:survivors]
        lines += ["", "### Surviving mutants", "", *survivor_lines(findings)] unless findings.empty?
        "#{lines.join("\n")}\n"
      end

      def rows(report)
        by_file = report.results.group_by { |result| relative(report, result.subject.file) }
        untested = untested_by_file(report)
        (by_file.keys | untested.keys).sort.map do |file|
          score = Score.of(by_file.fetch(file, []))
          cell = score.value ? "#{format('%.1f%%', score.value * 100)} (#{score.detected}/#{score.tested})" : "n/a"
          names = untested.fetch(file, [])
          "| #{file} | #{cell} | #{names.empty? ? '0' : "#{names.size}: #{names.join(', ')}"} |"
        end
      end

      def survivor_lines(findings)
        findings.map do |finding|
          "- `#{finding[:digest]}` #{finding[:path]}:#{finding[:line]} (#{finding[:operator]}): " \
            "#{inline_code(finding[:original])} -> #{inline_code(finding[:replacement])}"
        end
      end

      def untested_by_file(report)
        report.skipped_subjects.select { |_, reason| reason == ScoreTable::NO_COVERAGE }
              .keys.group_by { |subject| relative(report, subject.file) }
              .transform_values { |subjects| subjects.map(&:id) }
      end

      def relative(report, file)
        file.delete_prefix("#{report.root}/")
      end

      # Inline code fences itself with `` when the text holds a backtick.
      def inline_code(text)
        text.to_s.include?("`") ? "`` #{text} ``" : "`#{text}`"
      end
    end
  end
end
