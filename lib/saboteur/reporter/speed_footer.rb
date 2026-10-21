# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # PR16's speed footer: the run's wall time split by phase, so
    # "saboteur is slow" gets a number with an owner (Stryker and
    # cargo-mutants both print phase timings). A diagnostic, not part of
    # the clean screen: default runs print it only when an overhead phase
    # (baseline or map - never the mutant phase, which IS the work) ate
    # more than OVERHEAD_SHARE of the wall past OVERHEAD_FLOOR seconds;
    # --verbose always prints it.
    class SpeedFooter
      OVERHEAD_SHARE = 0.25
      OVERHEAD_FLOOR = 2.0
      # A mutant slower than SLOW_MUTANT_FACTOR times the median mutant
      # past SLOW_MUTANT_FLOOR seconds is an outlier worth naming.
      SLOW_MUTANT_FACTOR = 5
      SLOW_MUTANT_FLOOR = 1.0

      def initialize(out, palette, verbose: false)
        @out = out
        @palette = palette
        @verbose = verbose
      end

      def call(report)
        timings = report.phase_timings
        return unless timings
        return unless @verbose || overhead_exceeded?(timings, report.wall_time)

        @out.puts @palette.paint(:dim, line(timings, report.wall_time))
        outlier = slowest_outlier(report.results)
        return unless outlier

        @out.puts @palette.paint(:dim, "  slowest: #{outlier.subject.id} " \
                                       "(#{outlier.mutation.operator}, #{format('%.1f', outlier.runtime)}s)")
      end

      private

      def overhead_exceeded?(timings, wall_time)
        [timings.baseline_seconds, timings.map_seconds].any? do |seconds|
          seconds > OVERHEAD_FLOOR && seconds > wall_time * OVERHEAD_SHARE
        end
      end

      def line(timings, wall_time)
        map = timings.map_cached ? "0.0s (cached)" : "#{format('%.1f', timings.map_seconds)}s"
        "speed footer: done in #{format('%.1f', wall_time)}s - " \
          "baseline #{format('%.1f', timings.baseline_seconds)}s #{middot} map #{map} #{middot} " \
          "mutants #{format('%.1f', timings.mutants_seconds)}s (jobs=#{timings.jobs})"
      end

      def slowest_outlier(results)
        timed = results.select(&:runtime)
        return if timed.empty?

        slowest = timed.max_by(&:runtime)
        return unless slowest.runtime > SLOW_MUTANT_FLOOR && slowest.runtime > median(timed) * SLOW_MUTANT_FACTOR

        slowest
      end

      def median(results)
        runtimes = results.map(&:runtime).sort
        middle = runtimes.size / 2
        runtimes.size.odd? ? runtimes[middle] : (runtimes[middle - 1] + runtimes[middle]) / 2.0
      end

      def middot = @palette.glyph(:middot)
    end
  end
end
