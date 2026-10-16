# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../text"

module Saboteur
  class Engine
    # Review-shaped diff mode (--since). A reviewer asks "do the tests check
    # what this change did?", so only mutants on changed lines answer it.
    # The coarse mutants of each changed method still run: they ask whether
    # the method is tested at all.
    class DiffScope
      # changed_lines: { "/abs/file.rb" => Set[line numbers] }
      def initialize(changed_lines)
        @changed_lines = changed_lines
      end

      def restrict(subject, candidates)
        changed = lines_for(subject)
        candidates.select do |mutation, _|
          mutation.coarse || mutation.edits.any? { |edit| edited_lines(subject, edit).any? { changed.include?(_1) } }
        end
      end

      # The changed lines a mutant touches, sorted. A statement that spans
      # several lines is mutated as one piece and reported at its first line,
      # which can sit above the line that changed; this names the changed line.
      def changed_lines_for(subject, mutation)
        changed = lines_for(subject)
        mutation.edits.flat_map { |edit| edited_lines(subject, edit).to_a }.uniq.select { changed.include?(_1) }.sort
      end

      # Distance to the nearest changed line in this file. Unknown outside
      # the diff is nil, not a made-up nearby location. A range answers
      # geometrically - 0 when the edit overlaps, else the gap to the nearer
      # endpoint - so a whole-file range never materializes one entry per
      # line.
      def distance_for(subject, mutation)
        changed = lines_for(subject)
        mutation.edits.map do |edit|
          first, last = edited_lines(subject, edit).minmax
          if changed.is_a?(Range)
            if last < changed.begin then changed.begin - last
            elsif first > changed.end then first - changed.end
            else 0
            end
          else
            changed.map { |line| (line - line.clamp(first, last)).abs }.min
          end
        end.min
      end

      private

      # subject.file carries the locale tag under a non-UTF-8 locale
      # while the map keys are UTF-8; retag losslessly or a non-ASCII
      # path never matches and every fine mutant is silently dropped.
      def lines_for(subject)
        @changed_lines.fetch(Text.utf8_identity(subject.file), Set.new)
      end

      def edited_lines(subject, edit)
        first = subject.line_of(edit.start_byte)
        last = subject.line_of([edit.end_byte - 1, edit.start_byte].max)
        (first..last)
      end
    end
  end
end
