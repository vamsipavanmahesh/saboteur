# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # The incremental run's freshness, dim: what the cache reused and what
    # changed since those verdicts were recorded, plus the drift caveat.
    class ReuseSummary
      def initialize(out, palette)
        @out = out
        @palette = palette
      end

      def print(report)
        reuse = report.reuse
        stats = "mutants: #{pluralize(reuse.files_changed, 'file')} changed " \
                "(+#{reuse.added} -#{reuse.removed}) #{@palette.glyph(:middot)} " \
                "tests: #{pluralize(reuse.specs_changed, 'spec')} changed"
        @out.puts @palette.paint(:dim, "incremental: reused #{reuse.reused} of #{report.results.size} " \
                                       "verdicts - #{stats}")
        @out.puts @palette.paint(:dim, "  note: reuses verdicts for unchanged code and tests; " \
                                       "run without --incremental weekly")
      end

      private

      def pluralize(count, word) = "#{count} #{word}#{'s' unless count == 1}"
    end
  end
end
