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

      private

      def edited_lines(subject, edit)
        first = line_at(subject, edit.start_byte)
        last = line_at(subject, [edit.end_byte - 1, edit.start_byte].max)
        (first..last)
      end

      def line_at(subject, byte_offset)
        subject.file_source.byteslice(0, byte_offset).count("\n") + 1
      end
    end
  end
end
