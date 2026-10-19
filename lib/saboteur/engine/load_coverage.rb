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
        calls = boot_calls(wanted)
        CoverageReads.result(stop: false, clear: false)
                     .each_with_object([{}, {}]) do |(path, data), (lines_h, methods_h)|
          file = Selection::CoverageMap.canonical(path)
          next unless wanted.include?(file)

          called = calls.fetch(file, Set.new)
          lines = ran_lines(file, data, called)
          lines_h[file] = lines unless lines.empty?
          defs = called.map(&:first).uniq.sort
          methods_h[file] = defs unless defs.empty?
        end
      end

      def self.ran_lines(file, data, called)
        lines = data[:lines].each_with_index.filter_map { |count, index| index + 1 if count&.positive? }
        lines - uncalled_shared_lines(file, called)
      end

      # The def calls the executable's tracer saw while the app loaded,
      # file => Set of [line, name]. Coverage's methods report is off (its
      # per-read cost is what made the coverage map slow, #655).
      def self.boot_calls(wanted)
        tracer = MethodCalls.booted
        return {} unless tracer

        tracer.disable
        tracer.drain.each_with_object({}) do |(path, hits), by_file|
          file = Selection::CoverageMap.canonical(path)
          (by_file[file] ||= Set.new).merge(hits) if wanted.include?(file)
        end
      end

      # Include-listed files that are already loaded yet carry no coverage
      # instrumentation: something required them before the executable's
      # Coverage.start (a gemspec requiring the library while bundler/setup
      # evaluates it, or RUBYOPT -r), so no test can ever be attributed to
      # them. Read in the parent, where the snapshot still reflects the boot.
      def self.preloaded_uninstrumented(files, loaded: $LOADED_FEATURES)
        return [] unless Coverage.state == :suspended

        instrumented = CoverageReads.result(stop: false, clear: false)
                                    .each_key
                                    .to_set { |path| Selection::CoverageMap.canonical(path) }
        loaded_set = loaded.to_set { |path| Selection::CoverageMap.canonical(path) }
        files.map { |file| Selection::CoverageMap.canonical(file) }
             .uniq
             .reject { |file| instrumented.include?(file) }
             .select { |file| loaded_set.include?(file) }
      end

      # A one-line or endless definition executes its def line even when its
      # body is never called. If any sibling on that physical line is uncalled,
      # discard its ambiguous line evidence rather than crediting every body.
      def self.uncalled_shared_lines(file, called)
        defs = one_line_defs(file)
        defs.group_by(&:first).filter_map do |line, entries|
          line if entries.any? { |entry| !called.include?(entry) }
        end
      end

      DEFINERS = %i[define_method define_singleton_method].freeze

      # [line, name] for every def, or define_method with a block, that starts
      # and ends on one physical line. Coverage's methods report lists both.
      def self.one_line_defs(file)
        found = []
        walk = lambda do |node|
          name = definition_name(node)
          found << [node.location.start_line, name] if name && node.location.start_line == node.location.end_line
          node.compact_child_nodes.each(&walk)
        end
        walk.call(Prism.parse_file(file).value)
        found
      rescue SystemCallError
        []
      end

      def self.definition_name(node)
        return node.name if node.is_a?(Prism::DefNode)
        return unless node.is_a?(Prism::CallNode) && DEFINERS.include?(node.name) && node.block.is_a?(Prism::BlockNode)

        first = Array(node.arguments&.arguments).first
        first.unescaped.to_sym if first.is_a?(Prism::SymbolNode)
      end
    end
  end
end
