# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Baseline
    # Exact planned/result reconciliation, independent of survivor acceptance.
    class Completeness
      EXECUTED = %w[killed survived timeout].freeze
      # Soft gaps limit what the baseline can speak for; they never refuse a
      # proposal. Everything else is a hard blocker.
      SOFT_PREFIXES = %w[subject_skipped: omitted:].freeze
      attr_reader :issues

      def self.soft_gap?(issue)
        SOFT_PREFIXES.any? { |prefix| issue.start_with?(prefix) }
      end

      def initialize(planned:, results:, subjects:, stable_suite:, stable_inputs:, skipped_subjects:, omitted:,
                     generation_issues:)
        @issues = []
        issues << "unchanged_suite_incomplete" unless stable_suite
        issues << "inputs_unverified" unless stable_inputs
        validate_inventory(planned, subjects)
        inventory(planned, results)
        skipped_subjects.each { |entry| issues << "subject_skipped:#{entry}" }
        omitted.each { |entry| issues << "omitted:#{entry}" }
        generation_issues.each { |entry| issues << "generation:#{entry}" }
        @issues = issues.uniq.sort.freeze
      end

      def complete?
        issues.empty?
      end

      def blockers
        issues.reject { |issue| self.class.soft_gap?(issue) }
      end

      def gaps
        issues.select { |issue| self.class.soft_gap?(issue) }
      end

      # A proposal may be written over soft gaps (they are listed in it);
      # only hard blockers refuse.
      def proposable?
        blockers.empty?
      end

      private

      def validate_inventory(planned, subjects)
        issues << "empty_candidates" if planned.empty?
        issues << "empty_subjects" if subjects.empty?
        issues << "duplicate_subjects" unless subjects.uniq.size == subjects.size
        issues << "duplicate_candidates" unless planned.uniq.size == planned.size
      end

      def inventory(planned, results)
        observed = results.map { |entry| entry.fetch("id") }
        issues << "duplicate_results" unless observed.uniq.size == observed.size
        (planned - observed).each { |id| issues << "missing_result:#{id}" }
        (observed - planned).each { |id| issues << "unexpected_result:#{id}" }
        validate_results(results)
      end

      def validate_results(results)
        results.each do |entry|
          status = entry.fetch("status")
          issues << "unexecuted:#{entry.fetch('id')}:#{status}" unless EXECUTED.include?(status)
        end
      end
    end
  end
end
