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
    #
    # A line whose only change is its comment (a trailing "# note" added,
    # edited or removed) is not a code change either, and is dropped even
    # when the -b diff lists it. A `# saboteur:` comment is a directive, not
    # a note: adding, editing or removing one keeps the line.
    class LayoutOnlyLines
      LINE_KEYWORD = :KEYWORD___LINE__
      DIRECTIVE = /\A#\s*saboteur:/

      # hunks: [[old_start, old_count, new_start, new_count], ...] of the
      # whitespace-insensitive diff of one file, in order.
      def initialize(hunks, base_source:, current_source:)
        @hunks = hunks
        @base_tokens = tokens_by_line(base_source)
        @current_tokens = tokens_by_line(current_source)
        @base_code = code_by_line(base_source)
        @current_code = code_by_line(current_source)
      end

      # The -b diff's own lines, with its deletion markers, plus every line
      # of CHANGED whose tokens differ from its base line.
      def restrict(changed)
        (spaced_lines | changed.reject { |line| same_tokens?(line) }) - comment_only_lines
      end

      private

      def spaced_lines
        @hunks.each_with_object(Set.new) do |(_, _, start, count), lines|
          lines.merge(GitDiff.touched_lines(start, count))
        end
      end

      # Lines of a -b hunk that replaces as many lines as it removes, paired
      # in order, whose code is byte for byte the base line's and whose
      # comment is the only difference.
      def comment_only_lines
        @hunks.each_with_object(Set.new) do |(_, old_count, start, count), lines|
          next unless old_count == count

          lines.merge(GitDiff.touched_lines(start, count).select { |line| comment_only?(line) })
        end
      end

      def comment_only?(line)
        base_line = base_line_of(line)
        base_code, base_comment = @base_code[base_line]
        code, comment = @current_code[line]
        base_code == code && [base_comment, comment].none? { |text| text&.match?(DIRECTIVE) } &&
          !(base_line != line && moved_line_keyword?(line))
      end

      def moved_line_keyword?(line)
        @current_tokens[line].any? { |type, _| type == LINE_KEYWORD }
      end

      def same_tokens?(line)
        base_line = base_line_of(line)
        tokens = @current_tokens[line]
        return false if base_line != line && tokens.any? { |type, _| type == LINE_KEYWORD }

        tokens == @base_tokens[base_line]
      end

      # A line outside every hunk sits at its base position shifted by the
      # lines the hunks above it added or removed. A line inside a hunk is
      # one of the -b diff's own lines and is kept whatever this answers.
      def base_line_of(line)
        line - @hunks.sum { |_, old_count, start, count| start + count <= line ? count - old_count : 0 }
      end

      # Every token on each line it spans, as type and text. Every line has
      # one (a blank line its newline, text after __END__ that token), and a
      # missing line reads as [] through the default. A token that
      # spans lines (a heredoc body, a multi-line string) belongs to each.
      # A token's location ends after its last byte, so one that ends in a
      # newline would reach into the next line without this.
      def tokens_by_line(source)
        Prism.lex(source).value.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(token, _), lines|
          next if token.type == :EOF

          token.location.start_line.upto(last_line(token)) { |line| lines[line] << [token.type, token.value] }
        end
      end

      # Each line as [its text before a trailing comment, that comment or
      # nil]. A line a token continues from above has no comment of its own.
      def code_by_line(source)
        lines = source.lines
        map = lines.each_with_index.to_h { |text, index| [index + 1, [text.rstrip]] }
        comments = Prism.lex(source).value.filter_map { |token, _| token.location if token.type == :COMMENT }
        comments.each do |location|
          code = lines[location.start_line - 1].byteslice(0, location.start_column)
          map[location.start_line] = [code.rstrip, location.slice.rstrip]
        end
        map
      end

      def last_line(token)
        location = token.location
        token.value.end_with?("\n") ? location.end_line - 1 : location.end_line
      end
    end
  end
end
