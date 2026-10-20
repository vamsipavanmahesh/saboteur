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

      # { result: :match | :superset | :mismatch, match: bool, total: Integer, extra: Integer,
      #   gained: Integer,
      #   differences: [{kind:, name:}] } with at most MAX_DIFFERENCES entries,
      # sorted by kind and name.
      #
      # :superset means the partial map credits tests the full map does not,
      # on lines the full map also credits, and never lacks a credit the
      # full map has. Anything else that differs is :mismatch, including an
      # extra credit on a line the full map calls uncovered: it would turn
      # "no test covers this" into "covered". Those are counted apart, in
      # gained. extra counts the other extra credits (one per file, line and
      # test) in lines, methods and branches.
      def call(partial, full, fallback_files: [])
        maps = [partial, full]
        found = evidence_differences(maps) + dependency_differences(maps, fallback_files)
        counted = found.select { |item| KINDS.map(&:to_s).include?(item[:kind]) }
        extra = counted.sum { |item| item[:extra] }
        gained = counted.sum { |item| item[:gained] }
        result = if found.empty? then :match
                 elsif gained.positive? || found.any? { |item| item[:missing] } then :mismatch
                 else :superset
                 end
        shown = found.sort_by { |item| [item[:kind], item[:name]] }.first(MAX_DIFFERENCES)
        { result: result, match: result == :match, total: found.size, extra: extra, gained: gained,
          differences: shown.map { |item| item.slice(:kind, :name) } }
      end

      def evidence_differences(maps)
        partial, full = maps
        found = []
        unless partial.tests.sort == full.tests.sort
          found << { kind: "tests", name: "the set of test ids", missing: true }
        end
        KINDS.each { |kind| found.concat(hit_differences(kind.to_s, hits(partial, kind), hits(full, kind))) }
        found.concat(exact_differences("load", load_hits(partial), load_hits(full)))
      end

      # Per name: the credits only the partial map has (extra) and the ones
      # only the full map has (missing).
      def hit_differences(kind, left, right)
        (left.keys | right.keys).filter_map do |name|
          extra, gained, missing = credits(left[name] || {}, right[name] || {})
          next if extra.zero? && gained.zero? && !missing

          { kind: kind, name: name, extra: extra, gained: gained, missing: missing }
        end
      end

      def credits(left, right)
        extra = gained = 0
        missing = false
        (left.keys | right.keys).each do |line|
          mine = left[line] || []
          theirs = right[line] || []
          (theirs.empty? ? gained += mine.size : extra += (mine - theirs).size)
          missing ||= (theirs - mine).any?
        end
        [extra, gained, missing]
      end

      def exact_differences(kind, left, right)
        (left.keys | right.keys).reject { |name| left[name] == right[name] }
                                .map { |name| { kind: kind, name: name, missing: true } }
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

      # The files every verdict depends on must match exactly. What each
      # test depends on follows from its line and method credits, which are
      # compared above, so it is not compared again.
      def dependency_differences(maps, fallback_files)
        partial, full = maps
        left = dependencies(partial, fallback_files)
        right = dependencies(full, fallback_files)
        left.keys.reject { |name| left[name] == right[name] }.map { |name| { kind: "deps", name: name, missing: true } }
      end

      def dependencies(map, fallback_files)
        unobserved = (fallback_files | map.loaded_files).select { |file| map.empty_for?([file]) }.sort
        { "(boot files)" => map.boot_files, "(unobserved files)" => unobserved }
      end
    end
  end
end
