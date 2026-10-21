# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # CoverageStore's opt-in partial rebuild (#46): after a cache miss, start
    # from the last map and rerun only the spec files PartialInvalidation
    # calls stale. Anything short of a clean answer (no earlier map, a change
    # that needs a full rebuild, a failed rerun, an empty result) returns nil
    # and the caller builds the full map, so this can only save time.
    # Uses the store's @config, @root, @integration and @diagnostics and the
    # shadow helpers it shares (shadow_invalidation, shadow_rerun,
    # shadow_clean).
    module CoveragePartial
      # The full opt-in predicate, factored out for survivor confirmation
      # (#1063): partial coverage only applies to a cached, unscoped,
      # single-part run.
      def self.use?(config, parts)
        config["partial_coverage"] == "use" && config["cache"] && config["tests"].empty? && parts == 1
      end

      private

      # Same preconditions as the shadow run: a scoped or parted map is not
      # what a partial rebuild starts from.
      def partial_use?
        CoveragePartial.use?(@config, @parts)
      end

      def partial_map(files, note, preloaded)
        cache = @config.path("cache_dir")
        base = CoverageInputsSnapshot.latest(cache, @root)
        base_map = base && Selection::CoverageMap.load(CoverageInputsSnapshot.map_path(cache, base["map_key"]))
        return nil unless base_map

        stale = shadow_invalidation(base_map, files).stale_specs(base, note.current)
        return nil if stale == PartialInvalidation::FULL

        merged = stale.empty? ? base_map : PartialMerge.call(base_map, shadow_rerun(files, stale, base["seed"]), stale)
        merged = merged.with_preloaded(preloaded)
        return nil if merged.tests.empty?

        refuse_empty_map(merged, files, preloaded)
        @diagnostics.inform("reusing the earlier coverage map, rerunning #{stale.size} of " \
                            "#{@integration.test_files.size} spec files")
        merged
      rescue BudgetPhaseTimeout
        raise
      rescue StandardError => e
        @diagnostics.warn("partial coverage failed, so the full map is built\n  #{shadow_clean(e.message)}")
        nil
      end
    end
  end
end
