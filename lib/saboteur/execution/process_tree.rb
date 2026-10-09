# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Execution
    # Every process descended from one forked child, tracked for as long as the
    # child is supervised.
    #
    # A process group is not containment: any descendant can call setpgid or
    # setsid (a nested saboteur run does exactly that) and leave the group.
    # Parent links survive that, so the tree is rebuilt from the process table
    # on every poll, and every pid ever seen in it is remembered, so a
    # descendant whose parent exits (re-parented to init) is still known.
    #
    # Identity is pid plus start time, so a recycled pid is never signalled.
    class ProcessTree
      Entry = Data.define(:pid, :ppid, :pgid, :rss_kb, :state, :started)

      COLUMNS = "pid=,ppid=,pgid=,rss=,stat=,lstart="

      # One snapshot of the process table: { pid => Entry }.
      def self.table
        out = IO.popen(["ps", "-A", "-o", COLUMNS], err: File::NULL, &:read)
        out.each_line.with_object({}) do |line, rows|
          pid, ppid, pgid, rss, state, *started = line.split
          next unless started.any?

          rows[pid.to_i] = Entry.new(pid: pid.to_i, ppid: ppid.to_i, pgid: pgid.to_i, rss_kb: rss.to_i,
                                     state: state, started: started.join(" "))
        end
      end

      attr_reader :root

      def initialize(root)
        @root = root
        @known = {} # pid => start time
      end

      # The live members: not zombies, same start time as when first seen.
      # Also starts tracking any new descendant (by parent link or by the
      # root's process group), so call it often while the tree runs.
      def live_members(table = self.class.table)
        grow(table)
        @known.filter_map do |pid, started|
          entry = table[pid]
          entry if entry && entry.started == started && !entry.state.start_with?("Z")
        end
      end

      # Count and resident memory of the live members. rss_baseline_kb is the
      # supervisor's own RSS: forked children share its pages, so only growth
      # beyond it is counted per process.
      def usage(rss_baseline_kb, table = self.class.table)
        live = live_members(table)
        growth = live.sum { |entry| [entry.rss_kb - rss_baseline_kb, 0].max }
        [live.size, growth]
      end

      # Stops every member (a stopped process cannot fork), rescans until no new
      # member appears, then kills them all. Returns the pids it killed.
      def kill_all(rounds: 20)
        killed = []
        rounds.times do
          live = stop_until_stable
          break if live.empty?

          live.each { |entry| signal("KILL", entry.pid) }
          killed.concat(live.map(&:pid))
          sleep 0.01
        end
        killed.uniq
      end

      private

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
