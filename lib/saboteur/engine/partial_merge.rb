# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # The map a partial rebuild produces (#46, step 3): the base map with all
    # evidence of the rerun spec files removed, plus the fresh map the child
    # recorded over just those files. Whole spec files are replaced, never
    # single examples, since a file's example ids can shift when it changes.
    # Load-time evidence, loaded files and preloaded files carry over from
    # both: every run boots the same app.
    module PartialMerge
      module_function

      def call(base, fresh, spec_files)
        specs = spec_files.to_set
        dropped = base.tests.select { |id| specs.include?(PartialInvalidation.spec_of(id)) }.to_set
        trimmed = Selection::CoverageMap.new(
          lines: without(base.lines, dropped), methods: without(base.methods, dropped),
          branches: without(base.branches, dropped), tests: base.tests.reject { |id| dropped.include?(id) },
          durations: base.durations.except(*dropped),
          load_lines: base.load_lines, load_methods: base.load_methods,
          loaded_files: base.loaded_files, preloaded: base.preloaded.to_a, build_seconds: base.build_seconds
        )
        Selection::CoverageMap.combine([trimmed, fresh])
      end

      # {file => {line-or-span => ids}} without the dropped ids. An entry left
      # with no test is removed, and so is a file left with no entry: a file
      # with no test behind it must read as no evidence, not as covered.
      def without(hits, dropped)
        hits.each_with_object({}) do |(file, by_line), acc|
          kept = by_line.transform_values { |ids| ids - dropped.to_a }
          kept.reject! { |_, ids| ids.empty? }
          acc[file] = kept unless kept.empty?
        end
      end
    end
  end
end
