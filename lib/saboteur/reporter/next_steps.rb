# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../survivor_guidance"
require_relative "survivor_ranking"

module Saboteur
  module Reporter
    # The footer under a run that left survivors: how to look at one, how to
    # accept one, and how to hand the run to an agent. Silent when nothing
    # survived, so a clean run stays short.
    class NextSteps
      # replay_command: digest -> the full, copy-pasteable replay command
      # carrying the run's own selection options, however long it gets
      # (#261). When no builder is wired the digest-only hint (with its
      # reassembly note) is the fallback.
      def initialize(out, palette, replay_command: nil)
        @out = out
        @palette = palette
        @replay_command = replay_command
      end

      def call(report)
        # The list's top finding leads: same review priority as the survivor
        # list, not raw execution order.
        survivor = SurvivorRanking.ordered(report, report.unignored_survivors).first
        return unless survivor

        @out.puts "\n#{@palette.paint(:head, 'Next steps:')}"
        command = @replay_command&.call(survivor.digest)
        if command
          @out.puts "  replay one survivor: #{@palette.paint(:info, command)}"
        else
          command = SurvivorGuidance.replay_command(survivor.digest, seed: report.seed)
          @out.puts "  replay one survivor: #{@palette.paint(:info, command)}"
          @out.puts "    #{SurvivorGuidance::REPLAY_CAVEAT}"
        end
        @out.puts "  #{SurvivorGuidance::IGNORE_INTRO}"
        @out.puts "    Saboteur.ignore do |i|"
        @out.puts "      #{SurvivorGuidance.ignore_entry(survivor.digest, survivor.subject.id)}"
        @out.puts "    end"
        @out.puts "  let an agent close the gaps: saboteur run --agent, with the same options"
      end
    end
  end
end
