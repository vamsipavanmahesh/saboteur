# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Compares the map a partial rebuild produced with the full map (#46,
    # step 3). The full map is the one a run uses; this only says whether the
    # partial path would have been right.
    #
    # Two things are compared, and both must match:
    # - the semantic evidence: which tests exist and, per source file, which
    #   tests hit which lines, methods and branch arms, and which lines ran
    #   while the app loaded. Durations, build time and the order of ids are
    #   left out, as are entries with no test.
    # - what the result cache would watch: for every test the source files
    #   it touched, plus the boot files and the loaded files nothing
    #   observed. Evidence that matches line by line but yields another
    #   dependency set is worse than a line mismatch, since the set decides
    #   whether an old verdict is reused.
    module ShadowComparison
      MAX_DIFFERENCES = 50
      KINDS = %i[lines methods branches].freeze

      module_function

      # { match: bool, total: Integer, differences: [{kind:, name:}] } with
      # at most MAX_DIFFERENCES entries, sorted by kind and name.
      def call(partial, full, fallback_files: [])
        maps = [partial, full]
        found = evidence_differences(maps) + dependency_differences(maps, fallback_files)
        { match: found.empty?, total: found.size,
          differences: found.sort_by { |item| [item[:kind], item[:name]] }.first(MAX_DIFFERENCES) }
      end

      def evidence_differences(maps)
        partial, full = maps
        found = []
        found << { kind: "tests", name: "the set of test ids" } unless partial.tests.sort == full.tests.sort
        KINDS.each { |kind| found.concat(hit_differences(kind.to_s, hits(partial, kind), hits(full, kind))) }
        found.concat(hit_differences("load", load_hits(partial), load_hits(full)))
      end

      def hit_differences(kind, left, right)
        (left.keys | right.keys).reject { |name| left[name] == right[name] }.map { |name| { kind: kind, name: name } }
      end

      # {file => {line-or-span => sorted ids}} without empty entries.
      def hits(map, kind)
        map.public_send(kind).each_with_object({}) do |(file, by_line), acc|
          kept = by_line.transform_values(&:sort).reject { |_line, ids| ids.empty? }
          acc[file] = kept unless kept.empty?
        end
      end

      def load_hits(map)
        [map.load_lines, map.load_methods].flat_map(&:to_a).each_with_object({}) do |(file, lines), acc|
          acc[file] = (acc.fetch(file, []) | lines).sort unless lines.empty?
        end
      end

      def dependency_differences(maps, fallback_files)
        partial, full = maps
        left = dependencies(partial, fallback_files)
        right = dependencies(full, fallback_files)
        (left.keys | right.keys).reject { |name| left[name] == right[name] }.map { |name| { kind: "deps", name: name } }
      end

      # What ResultCache#dependencies reads for each test, plus the files
      # every verdict depends on, keyed by test id (the others by name).
      def dependencies(map, fallback_files)
        per_test = map.invert_coverage.transform_values { |files| files.uniq.sort }
        unobserved = (fallback_files | map.loaded_files).select { |file| map.empty_for?([file]) }.sort
        per_test.merge("(boot files)" => map.boot_files, "(unobserved files)" => unobserved)
      end
    end
  end
end
