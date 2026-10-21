# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Selects a bounded list for each covered subject before workers fork.
    # Subject skips are not mutants and do not enter the mutation score.
    class CandidateSelection
      attr_reader :skipped_subjects, :selected, :unscoped_digests

      def initialize(candidates:, map:, limit:, diagnostics:, root: nil)
        @candidates = candidates
        @map = map
        @limit = limit
        @diagnostics = diagnostics
        @root = root
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
          @diagnostics.announce(skip_announcement(subject, reason)) if scope
          return @selected[subject] = []
        end

        warn_boot_once(subject)
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

      # A note, not a verdict (#575): every mutant still runs and scores.
      def warn_boot_once(subject)
        return unless @map.boot_once?(subject)

        @diagnostics.warn("#{subject.id}: verify a survivor here by mutating the file on disk\n  " \
                          "covered by every test and run at boot: mutants apply after boot, so a survivor " \
                          "can be a boot-once effect the suite cannot re-observe (#575)")
      end

      # A scoped no-coverage skip names the specs the run loaded: coverage
      # living in a sibling spec file is otherwise invisible, and the false
      # read is "untestable" when the truth is "not loaded" (#636). Names
      # at most five, like the other selection notes.
      def skip_announcement(subject, reason)
        line = "#{subject.id} (#{subject.location(@root)}): skipped (#{reason}); its change is not verified by this run"
        return line unless ["no coverage", "no tests"].include?(reason)

        loaded = @map.tests.map { |id| id.split("[").first.delete_prefix("./") }.uniq.sort
        names = loaded.empty? ? "none" : Text.name_list(loaded)
        "#{line} - loaded specs: #{names}; " \
          "other spec files may cover it, pass --test to load them"
      end

      # Load-only code is not "no coverage": it ran, just never inside a
      # test, and no forked test can re-run it (see CoverageMap::RAN_AT_LOAD).
      # "no coverage" splits two truths the report must not conflate (C3):
      # no test recorded anything in the subject's file ("no tests") vs
      # tests ran the file but never executed this method, as with a stub
      # ("no coverage").
      def skip_reason_for(subject)
        return Selection::CoverageMap::PRELOADED if @map.preloaded?(subject.file)
        unless @map.ran_at_load?(subject.file, subject.coverage_lines)
          return @map.empty_for?([subject.file]) ? "no tests" : "no coverage"
        end

        Selection::CoverageMap::RAN_AT_LOAD
      end
    end
  end
end
