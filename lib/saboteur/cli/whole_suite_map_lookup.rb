# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # The whole-suite coverage map a finished run hands to survivor
    # presentation, and the notice for a scoped run that has none.
    module WholeSuiteMapLookup
      private

      # No engine or no cache: no whole-suite map can exist, so the survivor
      # block keeps its legacy covered-by line over an impossible build (review C1).
      def whole_suite_map_for(engine, report)
        warn_survivors_unconfirmed(report, engine)
        return engine.whole_suite_coverage_map if engine&.whole_suite_map_lookup?

        Reporter::SurvivorList::NO_WHOLE_SUITE_LOOKUP
      end

      # A scoped run's survivors may be pinned by a spec it never loaded.
      # With no whole-suite map to check, say so once, even under --quiet
      # (#1286). Verdicts, score and exit code are unchanged.
      def warn_survivors_unconfirmed(report, engine)
        return if report.unignored_survivors.empty?
        return unless engine&.whole_suite_map_lookup? && engine.scoped_selection?
        return if engine.whole_suite_coverage_map

        @err.puts "saboteur: survivors unconfirmed: no whole-suite coverage map; " \
                  "run `saboteur run --all` to build one"
      end
    end
  end
end
