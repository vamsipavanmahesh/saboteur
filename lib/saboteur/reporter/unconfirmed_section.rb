# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "mutation_text"
require_relative "survivor_ranking"

module Saboteur
  module Reporter
    # Survivors whose covering tests were not all run (#1286): outside the
    # score and the exit code, so they get their own short list instead of
    # a place among the findings.
    class UnconfirmedSection
      LIMIT = 10

      # The count for the one-line (--quiet) tally, nil when there is none.
      def self.part(report)
        count = report.unconfirmed_survivors.size
        "#{count} unconfirmed" if count.positive?
      end

      def initialize(out, palette)
        @out = out
        @palette = palette
      end

      def call(report)
        pending = report.unconfirmed_survivors
        return if pending.empty?

        @out.puts @palette.paint(:head, "unconfirmed (covering tests not run) - #{pending.size}, not in the score")
        SurvivorRanking.ordered(report, pending).first(LIMIT).each { |result| @out.puts line(report, result) }
        @out.puts "  ... #{pending.size - LIMIT} more" if pending.size > LIMIT
        @out.puts
      end

      private

      def line(report, result)
        path = result.subject.file.delete_prefix("#{report.root}/")
        "  #{path}:#{MutationText.line(result)} #{result.subject.id} - #{result.digest} (#{result.unconfirmed_reason})"
      end
    end
  end
end
