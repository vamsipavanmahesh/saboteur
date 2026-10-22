# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # One wording for the score parenthetical and the not-scored note, so
    # the terminal screen and the HTML page never drift (#1145, #1146).
    module Wording
      module_function

      # detected counts timeouts, the tally does not: name both when a
      # timeout is in the number, or "killed" means two things in adjacent
      # lines (#1146).
      def detected_word(breakdown)
        breakdown.timeouts.positive? ? "killed or timed out" : "killed"
      end

      # A subject with no coverage may have tests that stub it away: the
      # honest claim is about execution, not existence (#1145).
      def no_execution(untested_count)
        untested_count == 1 ? "no test executes it" : "no test executes them"
      end

      # The score table's per-file note fragment: count, subject noun and
      # the execution claim in one shape (#1145).
      def untested_note(count)
        "#{count} subject#{'s' unless count == 1} - #{no_execution(count)}"
      end

      # The clean screen's one-line note for subjects no run scored.
      def untested_win_note(untested)
        ids = untested.map(&:id).join(", ")
        "#{untested.size} subject#{'s' unless untested.one?} not scored - #{no_execution(untested.size)}: #{ids}"
      end
    end
  end
end
