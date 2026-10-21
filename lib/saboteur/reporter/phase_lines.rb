# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # The wording of the clean screen's phase lines (baseline, coverage map).
    module PhaseLines
      private

      # #312: a built map says what it cost and that it is reused next run; a
      # cached one says so. Without :cached the plain cost form renders.
      def coverage_map_text
        count = @coverage[:tests]
        tests = "#{count} #{count == 1 ? 'test' : 'tests'}"
        seconds = phase_seconds(@coverage[:seconds])
        case @coverage[:cached]
        when true then "coverage map: #{tests} (cached)"
        when false then "coverage map: built #{tests} (#{seconds}) - reused next run when the tree is unchanged"
        else "coverage map: #{tests} (#{seconds})"
        end
      end

      # The engine counts baseline passes; a caller that knows the example
      # count passes :examples instead.
      def baseline_text
        seconds = phase_seconds(@baseline[:seconds])
        return "baseline green (#{@baseline[:examples]} examples, #{seconds})" if @baseline[:examples]

        passes = @baseline[:passes]
        "baseline green (#{passes} #{passes == 1 ? 'pass' : 'passes'}, #{seconds})"
      end

      # Measured seconds, one decimal, without a trailing .0 (14s, 0.3s).
      def phase_seconds(seconds) = "#{format('%.1f', seconds).delete_suffix('.0')}s"
    end
  end
end
