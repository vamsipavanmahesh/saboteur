# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
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
    # A worker that dies has its item reported as an error and is replaced.
    class WorkerPool
      Worker = Struct.new(:number, :pid, :commands, :results, :current)

      # on_start: called in each worker with its number before its first
      # item (per-worker database connections, for example).
      def initialize(jobs:, on_start: nil)
        @jobs = jobs
        @on_start = on_start
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
          next unless worker

          line = io.gets
          next replace(worker, workers, queue, results, items, &work) unless line

          results[worker.current] = parse(line)
          assign(worker, queue)
          retire(worker, workers) unless worker.current
        end
        workers.reject { |worker| alive?(worker) }.each do |worker|
          replace(worker, workers, queue, results, items, &work)
        end
      end

      def parse(line)
        JSON.parse(line)
      rescue JSON::ParserError => e
        { "error" => "unreadable result from worker: #{e.message}" }
      end

      def alive?(worker)
        Process.waitpid(worker.pid, Process::WNOHANG).nil?
      rescue Errno::ECHILD
        false
      end

      def replace(worker, workers, queue, results, items, &)
        results[worker.current] = { "error" => "worker #{worker.number} died running this item" } if worker.current
        retire(worker, workers)
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
        Worker.new(number, pid, commands_write, results_read, nil)
      end

      # Runs in the worker until the parent closes its command pipe.
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
      rescue Exception # rubocop:disable Lint/RescueException
        exit!(1)
      end

      def run_one(item, &work)
        work.call(item)
      rescue StandardError => e
        { "error" => "#{e.class}: #{e.message}" }
      end

      # Closing the command pipe ends the worker's loop; anything it left
      # running is killed with its tree.
      def stop(worker)
        worker.commands.close unless worker.commands.closed?
        tree = Supervisor.live.delete(worker.pid)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        sleep 0.01 until reaped?(worker.pid) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        tree&.kill_all
        reaped?(worker.pid) || Process.wait(worker.pid)
        worker.results.close unless worker.results.closed?
      rescue Errno::ECHILD
        nil
      end

      def own_group(pid)
        Process.setpgid(pid, pid)
      rescue Errno::EACCES, Errno::ESRCH, Errno::EPERM
        nil
      end

      def reaped?(pid)
        !Process.waitpid(pid, Process::WNOHANG).nil?
      rescue Errno::ECHILD
        true
      end
    end
  end
end
