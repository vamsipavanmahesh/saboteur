# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require_relative "../text"
require_relative "process_tree"
require_relative "supervisor"

module Saboteur
  module Execution
    # Runs a block over items on several worker processes forked from the
    # booted parent, and returns the block's results in item order.
    #
    # Workers are processes, not threads: forking a mutant child from a
    # threaded parent is unsafe, and processes keep each worker's state
    # (and database connection) apart. Each worker takes one item at a time
    # from the parent, so a slow item does not hold up the rest; biggest
    # items go first when weights are given. Results travel back as JSON,
    # so the block must return plain data.
    #
    # Workers are numbered from 0; TEST_ENV_NUMBER follows the parallel test
    # convention Rails apps use for one database per worker ("", "2", "3").
    # A worker that dies has its item reported as an error, with the reason
    # (what it raised, or the signal), and is replaced. When workers keep
    # dying before finishing a single item, the pool stops with that reason.
    class WorkerPool
      # done: items finished; status: the Process::Status once reaped;
      # last_words: what the worker reported before dying, if anything.
      Worker = Struct.new(:number, :pid, :commands, :results, :current, :done, :status, :last_words)
      START_FAILURES = 3

      # on_start: called in each worker with its number before its first
      # item (per-worker database connections, for example).
      def initialize(jobs:, on_start: nil, on_result: nil)
        @jobs = jobs
        @on_start = on_start
        @on_result = on_result
        @start_failures = 0
      end

      def map(items, weights: nil, &work)
        order = items.each_index.sort_by { |index| [-(weights ? weights[index] : 0), index] }
        return inline(items, order, &work) if @jobs <= 1

        distribute(items, order, &work)
      end

      private

      def inline(items, order, &work)
        order.each_with_object(Array.new(items.size)) { |index, results| results[index] = work.call(items[index]) }
      end

      def distribute(items, order, &work)
        results = Array.new(items.size)
        queue = order.dup
        workers = []
        [@jobs, items.size].min.times { |number| workers << start(number, items, workers, &work) }
        workers.each { |worker| assign(worker, queue) }
        collect(workers, queue, results, items, &work) until workers.empty?
        results
      ensure
        workers&.each { |worker| stop(worker) }
      end

      # Waits up to a second for results, then checks for workers that died
      # without closing their pipe (a stray grandchild may still hold it).
      def collect(workers, queue, results, items, &work)
        ready = IO.select(workers.map(&:results), nil, nil, 1)&.first || []
        ready.each do |io|
          worker = workers.find { |candidate| candidate.results == io }
          receive(worker, workers, queue, results, items, &work) if worker
        end
        workers.reject { |worker| alive?(worker) }.each do |worker|
          replace(worker, workers, queue, results, items, &work)
        end
      end

      # Reads one line from a worker whose pipe is ready, then gives it its
      # next item, retires it when none is left, or replaces it if it died.
      def receive(worker, workers, queue, results, items, &)
        line = worker.results.gets
        take_and_report(worker, line, results) if line
        return replace(worker, workers, queue, results, items, &) if line.nil? || worker.last_words

        assign(worker, queue)
        retire(worker, workers) unless worker.current
      end

      # Records one result line, then reports the arrival before the worker
      # gets more work: a watcher (the canary) can raise here and stop every
      # queued item from starting (issue #102).
      def take_and_report(worker, line, results)
        current = worker.current
        take(worker, line, results)
        @on_result&.call(current, results[current]) if current && results[current]
      end

      def parse(line)
        JSON.parse(Text.utf8_strict(line))
      rescue JSON::ParserError => e
        { "error" => "unreadable result from worker: #{e.message}" }
      end

      def alive?(worker)
        !reaped?(worker)
      end

      # Stores a line from the worker: its item's result, or why it crashed.
      def take(worker, line, results)
        data = parse(line)
        return worker.last_words = data["fatal"] if data.key?("fatal")
        return unless worker.current

        results[worker.current] = data
        worker.done += 1
        worker.current = nil
      end

      # Reads what a dead worker left in its pipe: a last result, or why it
      # crashed.
      def drain(worker, results)
        pending = worker.results.read_nonblock(1 << 20, exception: false)
        return unless pending.is_a?(String)

        pending.each_line { |line| take_and_report(worker, line, results) if line.end_with?("\n") }
      rescue IOError
        nil
      end

      def replace(worker, workers, queue, results, items, &)
        drain(worker, results)
        retire(worker, workers)
        reason = worker.last_words || "worker #{worker.number} died#{how(worker.status)}"
        if worker.current
          # The synthetic error row takes the same arrival path as a normal
          # result, so the canary still trips when the dead worker damaged
          # the tree before dying (issue #102).
          results[worker.current] = { "error" => "#{reason}, running this item" }
          @on_result&.call(worker.current, results[worker.current])
        end
        give_up(reason) if worker.done.zero?
        return if queue.empty?

        fresh = start(worker.number, items, workers, &)
        workers << fresh
        assign(fresh, queue)
      end

      # Sends the worker the next item, if any; worker.current is nil after
      # when there was none left.
      def assign(worker, queue)
        worker.current = queue.shift
        return unless worker.current

        worker.commands.puts(worker.current)
        worker.commands.flush
      rescue Errno::EPIPE, IOError
        queue.unshift(worker.current) # the worker died before taking it
        worker.current = nil
      end

      def how(status)
        return "" unless status
        return " (signal #{Signal.signame(status.termsig)})" if status.signaled?

        " (exit #{status.exitstatus})"
      end

      # A worker that never finishes an item is a broken setup (on_start, a
      # bug in the work itself), not bad luck: stop instead of failing every
      # item one by one.
      def give_up(reason)
        @start_failures += 1
        raise Error, "workers keep failing to start: #{reason}" if @start_failures >= START_FAILURES
      end

      def retire(worker, workers)
        workers.delete(worker)
        stop(worker)
      end

      # siblings: workers already running. The new worker closes its copies
      # of their pipe ends, or a sibling would never see its command pipe
      # close (end of input) when the parent is done with it.
      def start(number, items, siblings, &work)
        commands_read, commands_write = IO.pipe
        results_read, results_write = IO.pipe
        pid = fork do
          siblings.each { |sibling| [sibling.commands, sibling.results].each(&:close) }
          commands_write.close
          results_read.close
          serve(number, items, commands_read, results_write, &work)
        end
        commands_read.close
        results_write.close
        own_group(pid)
        Supervisor.live[pid] = ProcessTree.new(pid)
        Worker.new(number, pid, commands_write, results_read, nil, 0)
      end

      # Runs in the worker until the parent closes its command pipe. If it
      # crashes, its last line says why.
      def serve(number, items, commands, results, &)
        Process.setpgid(0, 0)
        Supervisor.reset_in_worker!
        Supervisor.close_in_child.push(commands, results)
        ENV["SABOTEUR_WORKER"] = number.to_s
        ENV["TEST_ENV_NUMBER"] = number.zero? ? "" : (number + 1).to_s
        @on_start&.call(number)
        while (line = commands.gets)
          results.puts(JSON.generate(run_one(items[Integer(line)], &)))
          results.flush
        end
        exit!(0)
      rescue Exception => e # rubocop:disable Lint/RescueException
        last_words(results, "worker #{number} crashed: #{e.class}: #{e.message} (#{e.backtrace&.first})")
        exit!(1)
      end

      def last_words(results, message)
        results.puts(JSON.generate("fatal" => message))
        results.flush
      rescue StandardError
        nil
      end

      def run_one(item, &work)
        work.call(item)
      rescue Error => e
        # A tool error (a vanished cache dir, ...) aborts the run with
        # exit 3; it is not a per-mutant outcome. Serialize it so the
        # parent can re-raise it as itself (#283).
        { "tool_error" => e.message }
      rescue StandardError => e
        { "error" => "#{e.class}: #{e.message}" }
      end

      # Closing the command pipe ends the worker's loop; anything it left
      # running is killed with its tree.
      def stop(worker)
        worker.commands.close unless worker.commands.closed?
        tree = Supervisor.live.delete(worker.pid)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        sleep 0.01 until reaped?(worker) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        tree&.kill_all
        worker.status ||= Process.wait2(worker.pid).last unless reaped?(worker)
        worker.results.close unless worker.results.closed?
      rescue Errno::ECHILD
        nil
      end

      def own_group(pid)
        Process.setpgid(pid, pid)
      rescue Errno::EACCES, Errno::ESRCH, Errno::EPERM
        nil
      end

      # Reaps the worker if it has exited, keeping its status.
      def reaped?(worker)
        return true if worker.status

        pid, status = Process.waitpid2(worker.pid, Process::WNOHANG)
        worker.status = status if pid
        !pid.nil?
      rescue Errno::ECHILD
        true
      end
    end
  end
end
