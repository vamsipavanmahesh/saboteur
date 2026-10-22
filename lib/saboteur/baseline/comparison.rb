# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Baseline
    # Classifies evidence without suppressing a mutant or changing its score.
    class Comparison
      CATEGORY_NAMES = %w[accepted new changed resolved_kills detected_timeouts unmatched errors].freeze
      EXITS = { "clean" => 0, "review_required" => 1, "incompatible" => 2, "incomplete" => 3 }.freeze

      SCORED_STATUSES = %w[killed timeout survived].freeze
      DETECTED_STATUSES = %w[killed timeout].freeze

      attr_reader :state, :categories, :issues, :score

      # epsilon is the largest score drop, in percentage points, that still
      # passes. nil turns the score gate off.
      def initialize(baseline:, current:, epsilon: nil)
        @issues = current.fetch("issues").dup
        @categories = {}
        unless baseline.fetch("compatibility") == current.fetch("compatibility")
          @issues << "baseline inputs or operator policy changed; re-propose with baseline propose"
          @state = "incompatible"
          return
        end

        @categories = classify(baseline, current)
        @score = score_change(baseline, current, epsilon) if epsilon
        @state = outcome(current)
      end

      def exit_code
        EXITS.fetch(state)
      end

      private

      def classify(baseline, current)
        categories = CATEGORY_NAMES.to_h { |name| [name, []] }
        previous = baseline.fetch("accepted").to_h { |entry| [entry.fetch("id"), entry] }
        uncovered = uncovered_ids(current)
        current.fetch("candidates").each do |entry|
          next if uncovered.include?(entry.fetch("id"))

          accepted = previous.delete(entry.fetch("id"))
          name = category(entry, accepted)
          categories.fetch(name) << entry if name
        end
        categories["unmatched"] = previous.values
        categories.each_value { |entries| entries.sort_by! { |entry| order(entry) } }
        categories
      end

      # Mutants on lines no test runs are listed as gaps, never as errors.
      def uncovered_ids(current)
        Completeness.uncovered_ids(current.fetch("gaps", []))
      end

      def category(entry, accepted)
        case entry.fetch("status")
        when "survived"
          return "new" unless accepted
          return "accepted" if entry["context"] == accepted.fetch("context")

          "changed"
        when "killed" then accepted && "resolved_kills"
        when "timeout" then accepted && "detected_timeouts"
        else "errors"
        end
      end

      def outcome(current)
        # The proposability tier is the comparability gate: a run over soft
        # gaps still speaks for the subjects it executed. Legacy documents
        # without the split fall back to the strict flag and full issue list.
        proposable = current.fetch("proposable") { current.fetch("complete") }
        blockers = current.fetch("blockers") { current.fetch("issues") }
        return "incomplete" unless proposable && blockers.empty? && !current.fetch("candidates").empty?
        return "incomplete" unless categories.fetch("errors").empty?
        return "review_required" if %w[new changed unmatched].any? { |name| !categories.fetch(name).empty? }
        return "review_required" if score&.fetch("exceeded")

        "clean"
      end

      # Percent of scored mutants that were detected, as saboteur's own score
      # counts them: killed and timed out over killed, timed out and survived.
      # An exact Rational, so the drop is compared with epsilon without
      # binary float error.
      def detected_counts(candidates)
        scored = candidates.select { |entry| SCORED_STATUSES.include?(entry.fetch("status")) }
        return nil if scored.empty?

        [scored.count { |entry| DETECTED_STATUSES.include?(entry.fetch("status")) }, scored.size]
      end

      def score_change(baseline, current, epsilon)
        before = detected_counts(baseline.fetch("candidates"))
        now = detected_counts(current.fetch("candidates"))
        return nil unless before && now

        accepted = Rational(before[0] * 100, before[1])
        measured = Rational(now[0] * 100, now[1])
        drop = accepted - measured
        # The epsilon as the decimal the user typed, not its binary float. The
        # counts let a reader recompute the verdict exactly.
        { "baseline" => accepted.to_f, "current" => measured.to_f, "drop" => drop.to_f, "epsilon" => epsilon,
          "exceeded" => drop > Rational(epsilon.to_s),
          "baseline_detected" => before[0], "baseline_scored" => before[1],
          "current_detected" => now[0], "current_scored" => now[1] }
      end

      def order(entry)
        identity = entry.fetch("identity", [])
        [identity[1].to_s, identity[2].to_s, entry.fetch("id")]
      end
    end
  end
end
