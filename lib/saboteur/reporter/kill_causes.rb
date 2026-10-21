# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # How many kills came from a failed check and how many from a crash, and
    # which operators mostly kill by crashing (their score says less).
    class KillCauses
      def initialize(out)
        @out = out
      end

      def print(report)
        killed = report.results.select { |result| result.status == :killed }
        return if killed.empty?

        crashes = killed.select(&:crash_kill?)
        assertions = killed.count(&:assertion_kill?)
        unclassified = killed.size - assertions - crashes.size
        # String +, not interpolation: a nil piece must raise, not vanish.
        @out.puts "kills: #{assertions} by a failed assertion, #{crashes.size} by a crash" +
                  crash_classes(crashes) + unclassified_note(unclassified)
        @out.puts "crash kills by operator: #{by_operator(killed)}" if crashes.any?
      end

      private

      def crash_classes(crashes)
        return "" if crashes.empty?

        counts = crashes.map(&:kill_cause).tally.sort_by { |_, count| -count }
        " (#{counts.map { |name, count| "#{name} #{count}" }.join(', ')})"
      end

      def by_operator(killed)
        parts = killed.group_by { |result| result.mutation.operator }.filter_map do |operator, results|
          count = results.count(&:crash_kill?)
          "#{operator} #{count} of #{results.size}" if count.positive?
        end
        parts.join(", ")
      end

      # A kill with no recorded cause (an old cached verdict, a test that
      # called exit, a suite-level failure) is neither kind: count it apart
      # so the line adds up to the kills.
      def unclassified_note(count)
        return "" if count.zero?

        ", #{count} with cause not recorded"
      end
    end
  end
end
