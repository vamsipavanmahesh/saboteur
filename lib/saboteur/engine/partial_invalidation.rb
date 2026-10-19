# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Which spec files a partial coverage rebuild would have to rerun, or
    # :full when the whole map must be rebuilt (#46, step 2). Pure: it reads
    # two inputs snapshots and a coverage map and touches nothing else.
    #
    # An allowlist, not a blocklist. Coverage never records a test reading a
    # fixture, a YAML file, an ENV value or a template, so no changed file
    # can be proven harmless by absence. Only two kinds of change may take
    # the partial path: a spec file of the suite, and an included source
    # file with recorded coverage evidence that did not run while the app
    # loaded. Every other change, and every added or removed file, is :full,
    # as is a change of root, settings, runtime or snapshot format.
    #
    # The stale files come back in the order the map's full run used, so a
    # rerun keeps the relative order that run had.
    class PartialInvalidation
      FULL = :full
      # Placeholder, to be fitted from measurements; not configuration.
      THRESHOLD = 0.5
      SAME = %w[format root runtime settings].freeze

      # included: relative paths of the included source files.
      # spec_files: relative paths of the suite's spec files.
      # RSpec ids name their file: "./spec/a_spec.rb[1:2]" is spec/a_spec.rb.
      def self.spec_of(id)
        id.split("[").first.delete_prefix("./")
      end

      def initialize(map:, root:, included:, spec_files:)
        @map = map
        @root = Selection::CoverageMap.canonical(root)
        @included = included
        @spec_files = spec_files
      end

      def stale_specs(base, current)
        return FULL unless SAME.all? { |key| base[key] == current[key] }

        changed = changed_files([base, current].map { |snapshot| snapshot["files"] })
        return FULL unless changed

        stale = changed.each_with_object([]) do |file, specs|
          found = specs_for(file)
          return FULL unless found

          specs.concat(found)
        end
        ordered(stale.uniq).then { |specs| heavy?(specs) ? FULL : specs }
      end

      # The part of the recorded spec time these files hold, 0 when none was recorded.
      def share(specs)
        total = weights.values.sum
        total.zero? ? 0.0 : specs.sum { |file| weights.fetch(file, 0) }.fdiv(total)
      end

      private

      # nil when a file was added, removed or unreadable on either side.
      def changed_files(snapshots)
        before, after = snapshots
        return nil unless before.keys.sort == after.keys.sort
        return nil if (before.values + after.values).include?(false)

        before.keys.reject { |file| before[file] == after[file] }
      end

      def specs_for(file)
        return [file] if @spec_files.include?(file)
        return nil unless @included.include?(file) && evidence?(File.join(@root, file))

        touching(File.join(@root, file)).then { |specs| specs if specs.all? { |spec| @spec_files.include?(spec) } }
      end

      def evidence?(path)
        [@map.lines, @map.methods].any? { |hits| (hits[path] || {}).values.any?(&:any?) } &&
          [@map.load_lines, @map.load_methods].none? { |hits| hits[path]&.any? } &&
          !@map.preloaded?(path)
      end

      def touching(path)
        ids = [@map.lines, @map.methods].flat_map { |hits| (hits[path] || {}).values.flatten }
        ids.map { |id| spec_of(id) }.uniq
      end

      def spec_of(id)
        self.class.spec_of(id)
      end

      def ordered(stale)
        run_order = @map.tests.map { |id| spec_of(id) }.uniq
        run_order.select { |file| stale.include?(file) } + (stale - run_order).sort
      end

      # Stale share of the recorded time, by spec file, never above THRESHOLD.
      def heavy?(specs)
        total = weights.values.sum
        total.zero? || share(specs) > THRESHOLD
      end

      def weights
        @map.tests.group_by { |id| spec_of(id) }
            .transform_values { |ids| ids.sum { |id| @map.durations.fetch(id, 0) } }
      end
    end
  end
end
