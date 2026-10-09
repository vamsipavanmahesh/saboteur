# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "process_tree"
require_relative "protocol"

module Saboteur
  module Execution
    # Forks one child and owns everything it starts until a verdict is reached.
    #
    # Invariant: no process started on behalf of a child outlives that child's
    # supervision. Enforced by, in order:
    #   1. Tracking the whole descendant tree (ProcessTree), not just the
    #      process group, and killing all of it after every child, whether it
    #      passed, failed, crashed or timed out.
    #   2. A deadline, a memory cap and a process cap over the tree, checked
    #      while the child runs.
    #   3. Kernel backstops the tree tracking cannot miss: RLIMIT_CPU in the
    #      child, which every descendant inherits even if it escapes the tree,
    #      and a parent-death check in the child.
    #   4. Refusing recursion: the child is marked with CHILD_ENV, and Engine
    #      refuses to start a run inside a marked process.
    #   5. On Linux, the supervisor is a child subreaper, so escaped orphans are
    #      re-parented to it instead of init and stay in its tree.
    class Supervisor
      CHILD_ENV = "SABOTEUR_CHILD"

      Limits = Data.define(:max_memory_mb, :max_processes) do
        def self.default
          new(max_memory_mb: 2048, max_processes: 64)
        end
      end

      # payload: bytes the child wrote to its pipe. stop: nil when the child
      # finished on its own, else :timeout, :memory or :processes.
      Result = Data.define(:payload, :exit_status, :stopped_by, :detail, :runtime, :leftover_pids)

      POLL_INTERVAL = 0.5
      PR_SET_CHILD_SUBREAPER = 36
      TERM_GRACE = 1.0
      REAP_DEADLINE = 5.0

      @live = {}
      class << self
        attr_reader :live

        # Kills every tree still under supervision. Used on parent exit and on
        # INT/TERM, so Ctrl-C never leaves mutants running.
        def kill_live_trees
          live.each_value(&:kill_all)
          live.clear
        end

        def install_parent_handlers
          return if @installed

          @installed = true
          owner = Process.pid
          at_exit { kill_live_trees if Process.pid == owner }
          %w[INT TERM].each do |signal|
            previous = trap(signal) do
              kill_live_trees if Process.pid == owner
              previous.respond_to?(:call) ? previous.call : exit(128 + Signal.list.fetch(signal))
            end
          end
        end
      end

      def initialize(limits: Limits.default)
        @limits = limits
        self.class.install_parent_handlers
        become_subreaper
      end

      # Runs the block in a forked child with a pipe writer; the child exits
      # when the block returns. Returns a Result. cpu_seconds bounds every
      # descendant's CPU time (default: twice the deadline, at least 10 s).
      def run(timeout:, cpu_seconds: nil, &block)
        cpu_seconds ||= [(timeout * 2).ceil, 10].max
        reader, writer = IO.pipe
        $stdout.flush
        $stderr.flush
        started = monotonic
        supervisor = Process.pid
        pid = fork { child(reader, writer, supervisor, cpu_seconds, &block) }
        writer.close
        contain(pid, reader, started, timeout)
      ensure
        reader&.close unless reader&.closed?
      end

      private

      # --- child ----------------------------------------------------------

      def child(reader, writer, supervisor, cpu_seconds)
        reader.close
        ENV[CHILD_ENV] = "1"
        Process.setpgid(0, 0)
        limit_cpu(cpu_seconds)
        trap("TERM") { exit!(143) }
        watch_parent(supervisor)
        yield writer
        exit!(0)
      rescue Exception # rubocop:disable Lint/RescueException
        exit!(1)
      end

      # SIGXCPU at the soft limit, SIGKILL at the hard one. Limits can only be
      # lowered, so a nested supervisor stays within the one it inherited.
      def limit_cpu(seconds)
        _, hard = Process.getrlimit(Process::RLIMIT_CPU)
        hard_cap = hard == Process::RLIM_INFINITY ? seconds + 5 : [seconds + 5, hard].min
        Process.setrlimit(Process::RLIMIT_CPU, [seconds, hard_cap].min, hard_cap)
      end

      # macOS has no PDEATHSIG: poll, and exit if the supervisor is gone.
      def watch_parent(supervisor)
        Thread.new do
          loop do
            sleep 1
            exit!(1) if Process.ppid != supervisor
          end
        end
      end

      # --- parent ---------------------------------------------------------

      def contain(pid, reader, started, timeout)
        tree = ProcessTree.new(pid)
        self.class.live[pid] = tree
        own_group(pid)
        payload, stop, detail = watch(tree, reader, started + timeout)
        exit_status = stop == :timeout ? terminate(pid) : nil
        leftover_pids = tree.kill_all - [pid]
        exit_status ||= reap(pid)
        self.class.live.delete(pid)
        reap_adopted(leftover_pids)
        Result.new(payload: payload, exit_status: exit_status, stopped_by: stop, detail: detail,
                   runtime: monotonic - started, leftover_pids: leftover_pids)
      end

      # Reads until EOF, polling the tree's size and memory. Returns
      # [payload, stop, detail].
      def watch(tree, reader, deadline)
        payload = +""
        next_poll = monotonic + POLL_INTERVAL
        tree.live_members
        loop do
          now = monotonic
          return [payload, :timeout, "exceeded deadline"] if now >= deadline

          if now >= next_poll
            stop = over_limit(tree)
            return [payload, *stop] if stop

            next_poll = now + POLL_INTERVAL
          end
          next unless reader.wait_readable([deadline, next_poll].min - now)

          chunk = reader.read_nonblock(65_536, exception: false)
          break if chunk.nil?

          payload << chunk unless chunk == :wait_readable
        end
        [payload, nil, nil]
      end

      def over_limit(tree)
        count, growth_kb = tree.usage(baseline_rss_kb)
        if growth_kb > @limits.max_memory_mb * 1024
          [:memory, "process tree grew by #{growth_kb / 1024} MB (limit #{@limits.max_memory_mb} MB)"]
        elsif count > @limits.max_processes
          [:processes, "process tree reached #{count} processes (limit #{@limits.max_processes})"]
        end
      end

      # The supervisor's own RSS, refreshed at most every 10 s (forked children
      # share it, so it is the baseline for growth).
      def baseline_rss_kb
        now = monotonic
        if @baseline_at.nil? || now - @baseline_at > 10
          @baseline_rss_kb = ProcessTable.snapshot.fetch(Process.pid).rss_kb
          @baseline_at = now
        end
        @baseline_rss_kb
      end

      def terminate(pid)
        signal("TERM", -pid)
        deadline = monotonic + TERM_GRACE
        until monotonic > deadline
          status = waitpid(pid)
          return status if status

          sleep 0.01
        end
        nil
      end

      # Never blocks forever: the child was SIGKILLed by kill_all, so it is
      # reaped within milliseconds; give up after REAP_DEADLINE and say so.
      def reap(pid)
        deadline = monotonic + REAP_DEADLINE
        until monotonic > deadline
          status = waitpid(pid)
          return status if status

          signal("KILL", pid)
          sleep 0.01
        end
        :unreaped
      end

      def waitpid(pid)
        _, status = Process.waitpid2(pid, Process::WNOHANG)
        status
      rescue Errno::ECHILD
        :reaped
      end

      # With a subreaper (Linux), killed orphans were re-parented to us; reap
      # exactly those, never another child of the supervisor.
      def reap_adopted(pids)
        pids.each do |pid|
          Process.waitpid(pid, Process::WNOHANG)
        rescue Errno::ECHILD
          nil
        end
      end

      def own_group(pid)
        Process.setpgid(pid, pid)
      rescue Errno::EACCES, Errno::ESRCH, Errno::EPERM
        nil
      end

      def signal(name, target)
        Process.kill(name, target)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      def become_subreaper
        return unless RUBY_PLATFORM.include?("linux")

        require "fiddle"
        prctl = Fiddle::Function.new(Fiddle::Handle::DEFAULT["prctl"],
                                     [Fiddle::TYPE_INT, Fiddle::TYPE_LONG], Fiddle::TYPE_INT)
        prctl.call(PR_SET_CHILD_SUBREAPER, 1)
      rescue StandardError, Fiddle::DLError
        nil
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
