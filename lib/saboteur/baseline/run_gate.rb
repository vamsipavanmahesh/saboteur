# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "comparison"

module Saboteur
  module Baseline
    # The `saboteur run --baseline PATH` verdict: after a run, its execution
    # evidence is compared with the accepted baseline. Comparison owns the
    # classification and the decimal score gate; this names the run-surface
    # outcome: new survivors by digest or a score drop beyond the epsilon
    # fail the run, while accepted legacy survivors no longer do.
    class RunGate
      attr_reader :comparison

      def initialize(comparison)
        @comparison = comparison
      end

      def self.build(manifest:, report:, epsilon: nil)
        evidence = report.run_evidence
        raise Error, "--baseline needs the run's execution evidence; the run captured none" unless evidence

        new(Comparison.new(baseline: { "compatibility" => manifest.compatibility,
                                       "accepted" => manifest.accepted.values,
                                       "candidates" => manifest.candidates.values },
                           current: evidence, epsilon: epsilon))
      end

      def new_survivor_ids
        comparison.categories.fetch("new").map { |entry| entry.fetch("id") }
      end

      def incompatible?
        comparison.state == "incompatible"
      end

      def incomplete?
        comparison.state == "incomplete"
      end

      def score_exceeded?
        comparison.score ? comparison.score.fetch("exceeded") : false
      end

      def failed?
        new_survivor_ids.any? || score_exceeded?
      end
    end
  end
end
