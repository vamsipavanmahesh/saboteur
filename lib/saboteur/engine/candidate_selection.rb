# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Selects a bounded list for each covered subject before workers fork.
    # Subject skips are not mutants and do not enter the mutation score.
    class CandidateSelection
      attr_reader :skipped_subjects, :selected

      def initialize(candidates:, map:, limit:, diagnostics:)
        @candidates = candidates
        @map = map
        @limit = limit
        @diagnostics = diagnostics
        @skipped_subjects = {}
        @selected = {}
      end

      def for(subject, scope: nil)
        if @map.tests_for(subject).empty?
          @skipped_subjects[subject] = skip_reason_for(subject)
          return @selected[subject] = []
        end

        list = @candidates.for(subject)
        list = scope.restrict(subject, list) if scope
        omitted = list.size - @limit
        if omitted.positive?
          @diagnostics.record_omission(subject, count: omitted, limit: @limit)
          @diagnostics.warn("#{subject.id}: omitted #{omitted} mutant(s) above max_mutants_per_method (#{@limit})")
        end
        @selected[subject] = list.first(@limit)
      end

      private

      # Load-only code is not "no coverage": it ran, just never inside a
      # test, and no forked test can re-run it (see CoverageMap::RAN_AT_LOAD).
      def skip_reason_for(subject)
        return "no coverage" unless @map.ran_at_load?(subject.file, subject.coverage_lines)

        Selection::CoverageMap::RAN_AT_LOAD
      end
    end
  end
end
