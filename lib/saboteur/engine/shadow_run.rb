# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # One shadow comparison (#46, step 3): would a partial rebuild from the
    # last map have matched the full map this run just built? The run uses
    # the full map either way; this only produces the report.
    #
    # The report always carries the share threshold and, when the partial
    # path was possible, the observed stale share, so the constant can be
    # fitted from data later.
    module ShadowRun
      module_function

      # base: the earlier inputs snapshot and its map. current: the inputs
      # snapshot of this run. rerun.call(stale_spec_files, seed) builds a map
      # over just those files. clean turns a name into a line-safe string.
      def call(base:, base_map:, current:, full_map:, invalidation:, fallback_files:, rerun:, clean:)
        report = { "threshold" => PartialInvalidation::THRESHOLD, "base_map" => base["map_key"] }
        stale = invalidation.stale_specs(base, current)
        return report.merge("result" => "skipped", "reason" => "a full rebuild is needed") if stale == :full

        merged = stale.empty? ? base_map : PartialMerge.call(base_map, rerun.call(stale, base["seed"]), stale)
        verdict = ShadowComparison.call(merged, full_map, fallback_files: fallback_files)
        report.merge("result" => verdict[:result].to_s, "extra_credits" => verdict[:extra],
                     "stale" => stale.map(&clean),
                     "stale_share" => invalidation.share(stale), "total" => verdict[:total],
                     "differences" => verdict[:differences].map do |item|
                       item.to_h do |key, value|
                         [key.to_s, clean.call(value)]
                       end
                     end)
      end
    end
  end
end
