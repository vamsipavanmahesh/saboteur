# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # The closing block of a `run --baseline` report: what matched the
    # baseline, the verdict when the gate fails, and the re-baseline hint
    # that prints on every gated run, pass or fail.
    class BaselineTail
      def initialize(out, palette)
        @out = out
        @palette = palette
      end

      def call(gate, exit_code)
        @out.puts matched_line(gate)
        @out.puts @palette.paint(:fail, fail_verdict(gate)) if exit_code == 1
        @out.puts exit_code.zero? ? pass_hint : fail_hint
      end

      private

      def matched_line(gate)
        new_count = gate.new_survivor_ids.size
        return pass_line(gate) if new_count.zero?

        "saboteur: #{matched_count(gate)} matched the baseline#{breakdown(gate)} " \
          "#{@palette.glyph(:middot)} #{@palette.paint(:fail, counted(new_count, 'new survivor'))}"
      end

      def pass_line(gate)
        line = "saboteur: #{matched_count(gate)} matched the baseline, no new survivors"
        current, baseline = score_pair(gate)
        line << " - score #{current} (baseline #{baseline})" if current
        line
      end

      # Matched means the run's candidate was one the baseline had accepted:
      # still surviving (unchanged) or gone (fixed).
      def matched_count(gate)
        categories = gate.comparison.categories
        count = matched_parts(categories).sum
        "#{count} mutant#{'s' unless count == 1}"
      end

      def breakdown(gate)
        unchanged, fixed = matched_parts(gate.comparison.categories)
        parts = []
        parts << "#{unchanged} unchanged" if unchanged.positive?
        parts << "#{fixed} fixed" if fixed.positive?
        parts.empty? ? "" : " (#{parts.join(', ')})"
      end

      def matched_parts(categories)
        unchanged = categories.fetch("accepted").size + categories.fetch("changed").size
        fixed = categories.fetch("resolved_kills").size + categories.fetch("detected_timeouts").size
        [unchanged, fixed]
      end

      def fail_verdict(gate)
        reasons = []
        new_count = gate.new_survivor_ids.size
        reasons << counted(new_count, "new survivor") if new_count.positive?
        reasons << "score drop beyond epsilon" if gate.score_exceeded?
        line = "#{@palette.glyph(:cross)} exit 1 - #{reasons.join(' and ')} vs baseline"
        current, baseline = score_pair(gate)
        line << " (score #{current}, was #{baseline})" if current
        line
      end

      def score_pair(gate)
        score = gate.comparison.score
        return unless score

        [format("%.1f%%", score.fetch("current")), format("%.1f%%", score.fetch("baseline"))]
      end

      def counted(count, word)
        "#{count} #{word}#{'s' unless count == 1}"
      end

      def pass_hint
        @palette.paint(:dim, "re-baseline deliberately #{@palette.glyph(:middot)} " \
                             "run without --baseline weekly to catch drift")
      end

      def fail_hint
        "  #{@palette.paint(:dim, 're-baseline deliberately: saboteur baseline accept ' \
                                  "#{@palette.glyph(:middot)} run full weekly")}"
      end
    end
  end
end
