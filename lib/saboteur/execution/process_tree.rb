# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "process_table"
require_relative "marker_sweep"

module Saboteur
  module Execution
    # Every process descended from one forked child, tracked for as long as the
    # child is supervised.
    #
    # A process group is not containment: any descendant can call setpgid or
    # setsid (a nested saboteur run does exactly that) and leave the group.
    # Parent links survive that, so the tree is rebuilt from the process table
    # on every poll, and every pid ever seen in it is remembered, so a
    # descendant whose parent exits (re-parented to init) is still known -
    # but only if some poll SAW the parent link while the intermediate lived.
    # A descendant that leaves the group and loses that parent between two
    # polls is never seen (#365); the marker sweep in kill_all is the net
    # for exactly that case.
    #
    # Identity is pid plus start time, so a recycled pid is never signalled.
    class ProcessTree
      attr_reader :root

      def initialize(root, marker: nil)
        @root = root
        @marker = marker
        @known = {} # pid => start time
      end

      # The live members: not zombies, same start time as when first seen.
      # Also starts tracking any new descendant (by parent link or by the
      # root's process group), so call it often while the tree runs.
      def live_members(table = ProcessTable.snapshot)
        grow(table)
        @known.filter_map do |pid, started|
          entry = table[pid]
          entry if entry && entry.started == started && !entry.zombie
        end
      end

      # kill_all minus an excluded root, with the pre-kill member
      # descriptions: [killed pids, notes]. The notes are taken first -
      # after the kill the command lines are gone (#486).
      def kill_all_except(root)
        notes = describe_except(root)
        [kill_all - [root], notes]
      end

      # One "pid (command)" note per live member other than an excluded
      # root, for the leftover-children refusal (#486). Best effort: a
      # process that vanished mid-look lists its pid alone. Call before the
      # kill - after it, the command lines are gone.
      def describe_except(root, table = ProcessTable.snapshot)
        live_members(table).filter_map do |entry|
          next if entry.pid == root

          command = ProcessTable.command(entry.pid)
          command ? "#{entry.pid} (#{command})" : entry.pid.to_s
        end
      end

      # Count and resident memory of the live members. rss_baseline_kb is the
      # supervisor's own RSS: forked children share its pages, so only growth
      # beyond it is counted per process.
      def usage(rss_baseline_kb, table = ProcessTable.snapshot)
        live = live_members(table)
        growth = live.sum { |entry| [entry.rss_kb - rss_baseline_kb, 0].max }
        [live.size, growth]
      end

      # Stops every member (a stopped process cannot fork), rescans until no new
      # member appears, then kills them all. Each round also sweeps for
      # never-seen escapees carrying the run's marker (#365). Returns the
      # pids it killed.
      def kill_all(rounds: 20)
        killed = []
        rounds.times do
          live = stop_until_stable
          escaped = marked_escapees
          break if live.empty? && escaped.empty?

          live.each { |entry| signal("KILL", entry.pid) }
          signalled = escaped.select { |entry| escapee_alive?(entry) }
          signalled.each { |entry| signal("KILL", entry.pid) }
          killed.concat(live.map(&:pid), signalled.map(&:pid))
          sleep 0.01
        end
        killed.uniq
      end

      private

      # Live, non-zombie pids carrying the run's marker that the tree never
      # learned: the setsid-and-orphan escapees (#365). Members match the
      # marker too, but the same round kills them anyway.
      def marked_escapees
        return [] unless @marker && MarkerSweep.available?

        table = ProcessTable.snapshot
        root_started = @known[root]
        MarkerSweep.marked_pids(@marker, Supervisor::TREE_ENV).filter_map do |pid|
          entry = table[pid]
          next unless entry && !entry.zombie && !@known.key?(pid)

          # A process started before the run's root carries the marker only
          # through an exec chain the run did not spawn: never ours (#389).
          next if root_started && entry.started < root_started

          entry
        end
      end

      # A pid is not an identity: the escapee can exit between the sweep's
      # snapshot and the KILL, and the kernel can hand the pid to someone
      # else. Signal only the process the sweep actually saw (#389).
      def escapee_alive?(entry)
        fresh = ProcessTable.snapshot[entry.pid]
        fresh && !fresh.zombie && fresh.started == entry.started
      end

      def grow(table)
        @known[root] = table[root].started if @known.empty? && table[root]
        loop do
          added = table.values.select do |entry|
            next false if @known.key?(entry.pid) || entry.pid == Process.pid

            @known.key?(entry.ppid) || entry.pgid == root
          end
          break if added.empty?

          added.each { |entry| @known[entry.pid] = entry.started }
        end
      end

      def stop_until_stable
        stopped = {}
        5.times do
          live = live_members
          fresh = live.reject { |entry| stopped.key?(entry.pid) }
          return live if fresh.empty?

          fresh.each do |entry|
            signal("STOP", entry.pid)
            stopped[entry.pid] = true
          end
        end
        live_members
      end

      def signal(name, pid)
        Process.kill(name, pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
    end
  end
end
