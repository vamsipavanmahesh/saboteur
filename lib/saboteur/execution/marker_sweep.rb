# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fiddle"

module Saboteur
  module Execution
    # Finds the processes carrying a run's supervision marker (#365). A
    # descendant that leaves the child's process group and loses its
    # intermediate parent between two tree polls is invisible to
    # ProcessTree; the marker survives both escapes, in one of two
    # channels:
    #
    # comm - the child sets its /proc/<pid>/comm at start; fork copies it
    #        and setsid keeps it, so a fork-only descendant (Process.daemon)
    #        stays named. An exec or a self-rename (puma, sidekiq) drops it.
    # environ - /proc/<pid>/environ is frozen at each exec, so an exec'd
    #        descendant shows the environment it was started with, marker
    #        included; a fork-only descendant shows the top process's exec
    #        environment instead, which never had the marker - that path is
    #        what the comm channel covers.
    #
    # Linux only. Other platforms keep the gap from #365 rather than ship
    # an unverified parser.
    module MarkerSweep
      PR_SET_NAME = 15

      module_function

      # Best-effort: set this process's comm to the run's marker. comm - not
      # $0, which project code can read - survives fork and setsid; an exec
      # resets it, which the environment channel covers instead. Without a
      # usable prctl (macOS) the environment marker still names exec'd
      # descendants and the tree still tracks the rest.
      def write_comm(marker)
        prctl = Fiddle::Function.new(Fiddle::Handle::DEFAULT["prctl"],
                                     [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP] + ([Fiddle::TYPE_LONG] * 3),
                                     Fiddle::TYPE_INT)
        prctl.call(PR_SET_NAME, "#{Supervisor::COMM_PREFIX}#{marker}", 0, 0, 0)
        nil
      rescue StandardError, Fiddle::DLError
        nil
      end

      def available?
        File.exist?("/proc/self/environ")
      end

      # Live candidate pids marked in either channel. A process that exits
      # or turns unreadable mid-sweep is skipped; the caller's rounds see
      # what remains. The environment value is a colon-joined list so a
      # nested run keeps its ancestors' markers reachable.
      def marked_pids(marker, env_var)
        comm_name = "#{Supervisor::COMM_PREFIX}#{marker}"
        env_prefix = "#{env_var}="
        Dir.children("/proc").filter_map do |name|
          next unless name.match?(/\A\d+\z/)

          pid = name.to_i
          next if pid == Process.pid

          pid if comm_marked?(pid, comm_name) || environ_marked?(pid, env_prefix, marker)
        rescue SystemCallError, IOError
          nil
        end
      end

      def comm_marked?(pid, comm_name)
        File.read(File.join("/proc", pid.to_s, "comm")).chomp == comm_name
      end

      def environ_marked?(pid, env_prefix, marker)
        entries = File.binread(File.join("/proc", pid.to_s, "environ")).split("\0")
        value = entries.find { |entry| entry.start_with?(env_prefix) }&.[](env_prefix.length..)
        value&.split(":")&.include?(marker) || false
      end
    end
  end
end
