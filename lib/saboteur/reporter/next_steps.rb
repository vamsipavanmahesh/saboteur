# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # The footer under a run that left survivors: how to look at one, how to
    # accept one, and how to hand the run to an agent. Silent when nothing
    # survived, so a clean run stays short.
    class NextSteps
      IGNORE_FILE = "config/saboteur_ignore.rb"

      def initialize(out, palette)
        @out = out
        @palette = palette
      end

      def call(report)
        survivor = report.unignored_survivors.first
        return unless survivor

        @out.puts "\n#{@palette.paint(:bold, 'Next steps:')}"
        seed = " --seed #{report.seed}" if report.seed
        @out.puts "  replay one survivor: saboteur run --id #{survivor.digest}#{seed}"
        @out.puts "  accept an equivalent one: add its digest and a reason to #{IGNORE_FILE}"
        @out.puts "  let an agent close the gaps: saboteur run --format agent"
      end
    end
  end
end
