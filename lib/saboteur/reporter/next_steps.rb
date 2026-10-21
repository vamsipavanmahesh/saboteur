# SPDX-License-Identifier: MIT
# frozen_string_literal: true

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
        survivor = report.unignored_survivors.first
        return unless survivor

        @out.puts "\n#{@palette.paint(:head, 'Next steps:')}"
        command = @replay_command&.call(survivor.digest)
        if command
          @out.puts "  replay one survivor: #{@palette.paint(:info, command)}"
        else
          seed = " --seed #{report.seed}" if report.seed
          @out.puts "  replay one survivor: " \
                    "#{@palette.paint(:info, "saboteur run --id #{survivor.digest}#{seed}")}"
          @out.puts "    (add this run's own --config, --since, --subject, --test and source options)"
        end
        @out.puts "  accept an equivalent one: add to your ignore file (c.ignore_file, default #{Config::IGNORE_FILE}):"
        entry = %(i.mutation "#{survivor.digest}", subject: "#{survivor.subject.id}", reason: "why it is equivalent")
        @out.puts "    #{entry}"
        @out.puts "  let an agent close the gaps: saboteur run --agent, with the same options"
        @out.puts "  narrow the run: saboteur survivors #{Config::DEFAULTS['json_report']} " \
                  "(--file, --operator, --triage), or re-run with --since or --subject"
      end
    end
  end
end
