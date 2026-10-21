# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # The detail line a "mostly errored" or "incomplete" exit message adds:
    # the most common first line of the errored results' reasons, so a run
    # that exits on its error count still names why (a worker killed by a
    # signal, say) instead of leaving the cause in the stdout error list.
    module ErrorCause
      def self.incomplete(problem)
        "saboteur: #{problem.size} mutant(s) errored or hit a resource limit, so the score is " \
          "incomplete#{line(problem)}"
      end

      LIMIT = 200

      # The machine cause and the one-line human reason for the two exits no
      # report can describe, because the run never produced one. The verdict
      # line names the reason for a nonzero exit; the report-driven codes get
      # theirs from the terminal summary's verdict line.
      # Keyed by exit code. Literals for EXIT_BASELINE_RED and EXIT_CRASH:
      # this file loads before the CLI defines them; the cause pins spec
      # asserts the keys are those two constants.
      CAUSE_LINES = {
        5 => ["baselineRed", "baseline suite red: fix your tests first"],
        70 => ["crash", "internal crash (a saboteur bug, never your code)"]
      }.freeze

      def self.cause(code) = CAUSE_LINES.fetch(code).first

      def self.verdict_line(code) = "exit #{code} - #{CAUSE_LINES.fetch(code).last}"

      # "" when no result carries a reason.
      def self.line(errored)
        reasons = errored.filter_map { |result| first_line(result.reason) }.reject(&:empty?)
        return "" if reasons.empty?

        # Worker numbers and pids differ between otherwise identical deaths.
        group = reasons.group_by { |reason| reason.delete("0-9") }.values.max_by(&:size)
        "\n  most common cause (#{group.size} of #{errored.size}): #{group.first}"
      end

      # A reason can carry invalid bytes, terminal escapes or a huge line,
      # and this runs on the way to the exit code: scrub, escape controls and
      # cap before anything groups or prints it, and never raise.
      def self.first_line(reason)
        text = Text.utf8(reason.to_s).lines.map(&:strip).find { |line| !line.empty? }.to_s
        text = Text.display_safe(text.gsub(/\e\[[0-9;]*[A-Za-z]/, ""))
        text.length > LIMIT ? "#{text[0, LIMIT]}..." : text
      rescue StandardError
        reason.to_s.dump[0, LIMIT]
      end
    end
  end
end
