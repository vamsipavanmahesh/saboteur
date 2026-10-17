# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"

module Saboteur
  module Selection
    # Drops changed lines whose only change is layout (#313). Wrapping
    # existing statements in a block re-indents them; a plain diff marks
    # every one as changed, so their mutants run as if the change touched
    # them.
    #
    # A whitespace-insensitive diff (git diff -b) finds the lines that
    # differ by more than spacing and pairs every other line with its line
    # at the base. A changed line outside that diff is dropped only when
    # Prism lexes it to the same tokens as its base line: whitespace inside
    # a string, heredoc or regexp is part of a token, so it still counts as
    # a change. A `__LINE__` on a line that moved names another number, so
    # that line counts too.
    class LayoutOnlyLines
      LINE_KEYWORD = :KEYWORD___LINE__

      # hunks: [[old_start, old_count, new_start, new_count], ...] of the
      # whitespace-insensitive diff of one file, in order.
      def initialize(hunks, base_source:, current_source:)
        @hunks = hunks
        @base_tokens = tokens_by_line(base_source)
        @current_tokens = tokens_by_line(current_source)
      end

      # The -b diff's own lines, with its deletion markers, plus every line
      # of CHANGED whose tokens differ from its base line.
      def restrict(changed)
        spaced_lines | changed.reject { |line| same_tokens?(line) }
      end

      private

      def spaced_lines
        @hunks.each_with_object(Set.new) do |(_, _, start, count), lines|
          lines.merge(GitDiff.touched_lines(start, count))
        end
      end

      def same_tokens?(line)
        base_line = base_line_of(line)
        tokens = @current_tokens.fetch(line, [])
        return false if base_line != line && tokens.any? { |type, _| type == LINE_KEYWORD }

        tokens == @base_tokens.fetch(base_line, [])
      end

      # A line outside every hunk sits at its base position shifted by the
      # lines the hunks above it added or removed. A line inside a hunk is
      # one of the -b diff's own lines and is kept whatever this answers.
      def base_line_of(line)
        line - @hunks.sum { |_, old_count, start, count| start + count <= line ? count - old_count : 0 }
      end

      # Every token on each line it spans, as type and text. A token that
      # spans lines (a heredoc body, a multi-line string) belongs to each.
      # A token's location ends after its last byte, so one that ends in a
      # newline would reach into the next line without this.
      def tokens_by_line(source)
        Prism.lex(source).value.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(token, _), lines|
          next if token.type == :EOF

          token.location.start_line.upto(last_line(token)) { |line| lines[line] << [token.type, token.value] }
        end
      end

      def last_line(token)
        location = token.location
        token.value.end_with?("\n") ? location.end_line - 1 : location.end_line
      end
    end
  end
end
