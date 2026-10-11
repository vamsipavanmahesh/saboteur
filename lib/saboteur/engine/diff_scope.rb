# SPDX-License-Identifier: MIT
# frozen_string_literal: true

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
        changed = @changed_lines.fetch(subject.file, Set.new)
        candidates.select do |mutation, _|
          mutation.coarse || mutation.edits.any? { |edit| edited_lines(subject, edit).any? { changed.include?(_1) } }
        end
      end

      # The changed lines a mutant touches, sorted. A statement that spans
      # several lines is mutated as one piece and reported at its first line,
      # which can sit above the line that changed; this names the changed line.
      def changed_lines_for(subject, mutation)
        changed = @changed_lines.fetch(subject.file, Set.new)
        mutation.edits.flat_map { |edit| edited_lines(subject, edit).to_a }.uniq.select { changed.include?(_1) }.sort
      end

      private

      def edited_lines(subject, edit)
        first = subject.line_of(edit.start_byte)
        last = subject.line_of([edit.end_byte - 1, edit.start_byte].max)
        (first..last)
      end
    end
  end
end
