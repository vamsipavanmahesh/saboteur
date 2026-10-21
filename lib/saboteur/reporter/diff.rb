# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Minimal unified diff between two method texts (LCS over lines). Methods
    # are short, so the quadratic table is fine.
    module Diff
      CONTEXT = 3

      module_function

      def unified(original, mutated, path:, first_line: 1)
        a = original.lines
        b = mutated.lines
        ops = operations(a, b)
        hunks = hunks(ops)
        return "" if hunks.empty?

        out = "--- a/#{path}\n+++ b/#{path}\n"
        hunks.each { |hunk| out << render(hunk, first_line) }
        out
      end

      # [[:same|:del|:add, a_index, b_index, text]]
      def operations(old_lines, new_lines)
        a = old_lines
        b = new_lines
        table = lcs_table(a, b)
        ops = []
        i = 0
        j = 0
        while i < a.size || j < b.size
          if i < a.size && j < b.size && a[i] == b[j]
            ops << [:same, i, j, a[i]]
            i += 1
            j += 1
          elsif i < a.size && (j >= b.size || table[i + 1][j] >= table[i][j + 1])
            ops << [:del, i, j, a[i]]
            i += 1
          else
            ops << [:add, i, j, b[j]]
            j += 1
          end
        end
        ops
      end

      def lcs_table(old_lines, new_lines)
        a = old_lines
        b = new_lines
        table = Array.new(a.size + 1) { Array.new(b.size + 1, 0) }
        (a.size - 1).downto(0) do |i|
          (b.size - 1).downto(0) do |j|
            table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : [table[i + 1][j], table[i][j + 1]].max
          end
        end
        table
      end

      def hunks(ops)
        changed = ops.each_index.reject { |index| ops[index][0] == :same }
        return [] if changed.empty?

        ranges = changed.map { |index| [[index - CONTEXT, 0].max, [index + CONTEXT, ops.size - 1].min] }
        merged = ranges.each_with_object([]) do |(from, to), acc|
          if acc.any? && from <= acc.last[1] + 1
            acc.last[1] = [acc.last[1], to].max
          else
            acc << [from, to]
          end
        end
        merged.map { |from, to| ops[from..to] }
      end

      def render(hunk, first_line)
        a_start = hunk.first[1]
        b_start = hunk.first[2]
        a_count = hunk.count { |op| op[0] != :add }
        b_count = hunk.count { |op| op[0] != :del }
        out = "@@ -#{range(a_start + first_line, a_count)} +#{range(b_start + first_line, b_count)} @@\n"
        hunk.each do |op, _, _, text|
          prefix = { same: " ", del: "-", add: "+" }.fetch(op)
          out << prefix << text
          out << "\n" unless text.end_with?("\n")
        end
        out
      end

      # The [column, length] span a mutant's edits cover within their
      # line's replacement text: the exact replacement span (a pure
      # insertion still gets one caret), so a survivor block's ^^^ marker
      # sits under the changed text rather than a prefix/suffix guess.
      def edit_span(line_start_byte, edits)
        from = edits.map(&:start_byte).min - line_start_byte
        length = edits.sum { |edit| edit.replacement.partition("\n").first.size }
        [from, [length, 1].max]
      end

      def range(start, count)
        return "#{start - 1},0" if count.zero?

        count == 1 ? start.to_s : "#{start},#{count}"
      end
    end
  end
end
