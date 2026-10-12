# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Baseline
    # Classifies evidence without suppressing a mutant or changing its score.
    class Comparison
      CATEGORY_NAMES = %w[accepted new changed resolved_kills detected_timeouts unmatched errors].freeze
      EXITS = { "clean" => 0, "review_required" => 1, "incompatible" => 2, "incomplete" => 3 }.freeze

      attr_reader :state, :categories, :issues

      def initialize(baseline:, current:)
        @issues = current.fetch("issues").dup
        @categories = {}
        unless baseline.fetch("compatibility") == current.fetch("compatibility")
          @state = "incompatible"
          return
        end

        @categories = CATEGORY_NAMES.to_h { |name| [name, []] }
        previous = baseline.fetch("accepted").to_h { |entry| [entry.fetch("id"), entry] }
        current.fetch("candidates").each do |entry|
          accepted = previous.delete(entry.fetch("id"))
          name = category(entry, accepted)
          categories.fetch(name) << entry if name
        end
        categories["unmatched"] = previous.values
        categories.each_value { |entries| entries.sort_by! { |entry| order(entry) } }
        @state = outcome(current)
      end

      def exit_code
        EXITS.fetch(state)
      end

      private

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
        return "incomplete" unless current.fetch("complete") && issues.empty? && !current.fetch("candidates").empty?
        return "incomplete" unless categories.fetch("errors").empty?
        return "review_required" if %w[new changed unmatched].any? { |name| !categories.fetch(name).empty? }

        "clean"
      end

      def order(entry)
        identity = entry.fetch("identity", [])
        [identity[1].to_s, identity[2].to_s, entry.fetch("id")]
      end
    end
  end
end
