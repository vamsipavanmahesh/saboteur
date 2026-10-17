# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"

module Saboteur
  class Engine
    # The boot's coverage snapshot, read in the parent because a forked
    # child does not inherit Coverage counters: the lines and the def
    # calls that ran while the app and spec files loaded. The executable
    # counts from its first line, so this snapshot holds the whole boot.
    # The lines tell ran-at-load mutants apart from uncovered ones; the
    # def calls name def-time macros whose only caller ran here, so their
    # mutants read as ran at load instead of surviving on the pristine
    # closure (#409).
    module LoadCoverage
      # Returns [load_lines, load_methods]: file => line numbers for each.
      def self.capture(files)
        return [{}, {}] unless Coverage.state == :suspended

        wanted = files.to_set { |file| Selection::CoverageMap.canonical(file) }
        CoverageReads.result(stop: false, clear: false).each_with_object([{}, {}]) do |(path, data), (lines_h, methods_h)|
          file = Selection::CoverageMap.canonical(path)
          next unless wanted.include?(file)

          lines = data[:lines].each_with_index.filter_map { |count, index| index + 1 if count&.positive? }
          lines -= uncalled_shared_lines(data)
          lines_h[file] = lines unless lines.empty?
          defs = data.fetch(:methods, {}).filter_map { |(_owner, _name, first, *), count| first if count.positive? }
          methods_h[file] = defs.uniq.sort unless defs.empty?
        end
      end

      # A one-line or endless definition executes its def line even when its
      # body is never called. If any sibling on that physical line is uncalled,
      # discard its ambiguous line evidence rather than crediting every body.
      def self.uncalled_shared_lines(data)
        shared = data.fetch(:methods, {}).select { |(_owner, _name, first, _column, last, *), _| first == last }
        calls = shared.group_by { |(_owner, _name, first, *), _count| first }
        calls.filter_map { |line, entries| line if entries.any? { |_key, count| count.zero? } }
      end
    end
  end
end
