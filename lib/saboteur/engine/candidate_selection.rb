# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Selects a bounded list for each covered subject before workers fork.
    # Subject skips are not mutants and do not enter the mutation score.
    class CandidateSelection
      attr_reader :skipped_subjects

      def initialize(candidates:, map:, limit:, diagnostics:)
        @candidates = candidates
        @map = map
        @limit = limit
        @diagnostics = diagnostics
        @skipped_subjects = {}
      end

      def for(subject, scope: nil)
        if @map.tests_for(subject).empty?
          @skipped_subjects[subject] = "no coverage"
          return []
        end

        list = @candidates.for(subject)
        list = scope.restrict(subject, list) if scope
        omitted = list.size - @limit
        if omitted.positive?
          @diagnostics.warn("#{subject.id}: omitted #{omitted} mutant(s) above max_mutants_per_method (#{@limit})")
        end
        list.first(@limit)
      end
    end
  end
  end
