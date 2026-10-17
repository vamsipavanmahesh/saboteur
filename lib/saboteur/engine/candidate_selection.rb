# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Selects a bounded list for each covered subject before workers fork.
    # Subject skips are not mutants and do not enter the mutation score.
    class CandidateSelection
      attr_reader :skipped_subjects, :selected, :unscoped_digests

      def initialize(candidates:, map:, limit:, diagnostics:)
        @candidates = candidates
        @map = map
        @limit = limit
        @diagnostics = diagnostics
        @skipped_subjects = {}
        @selected = {}
        @unscoped_digests = {}
      end

      def for(subject, scope: nil)
        reason = subject.skip_reason || (skip_reason_for(subject) if @map.tests_for(subject).empty?)
        if reason
          @skipped_subjects[subject] = reason
          # In a scoped run every subject is part of the change under
          # review, so a skip is said up front, not only in the end-of-run
          # summary (#574).
          @diagnostics.announce("#{subject.id}: skipped (#{reason}); its change is not verified by this run") if scope
          return @selected[subject] = []
        end

        list = @candidates.for(subject)
        # The full pre-scope digests let IgnoreList#apply tell "mutation gone"
        # from "mutation scoped out of this run" (#284).
        if scope
          @unscoped_digests[subject.id] = list.map do |mutation, _|
            mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
          end
        end
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
