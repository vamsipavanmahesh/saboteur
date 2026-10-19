# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Execution
    # Several supervised children at once (#741), mixed into Supervisor. It
    # relies on Supervisor's start and contain.
    module SupervisorBatch
      # Runs count children at once, each supervised with the same limits and
      # deadline as run, and returns their Results in index order (#741). The
      # block gets (writer, index). Every child is forked from this thread
      # before any watcher thread exists, so no fork happens beside a live
      # thread; each child has its own copy of this supervisor, so its marker,
      # label and memory peak never mix with a sibling's. Watching runs on one
      # thread per child; on_tick is called only from the calling thread. A
      # child that fails or is stopped does not cut its siblings short: every
      # child is still contained and reaped before this returns, and the
      # caller decides what a failed part means.
      def run_many(count, timeout:, cpu_seconds: nil, on_tick: nil, label: "supervised child died", &block)
        raise ArgumentError, "count must be at least 1, got #{count}" if count < 1

        started = []
        begin
          count.times do |index|
            part = dup
            started << [part, *part.send(:start, timeout, cpu_seconds, label) { |writer| block.call(writer, index) }]
          end
        rescue Exception => e # rubocop:disable Lint/RescueException
          reap_started(started)
          raise e
        end
        watch_all(started, timeout, on_tick)
      end

      private

      # One watcher thread per started child. Waits for all of them, even
      # when one raises, so no child outlives this call; then re-raises the
      # first failure. When the calling thread's loop is interrupted (on_tick
      # raised, Interrupt), every child is killed at once instead of being
      # left to run to its deadline.
      def watch_all(started, timeout, on_tick)
        watchers = start_watchers(started, timeout)
        begin
          until watchers.none?(&:alive?)
            on_tick&.call
            sleep 0.01
          end
        rescue Exception # rubocop:disable Lint/RescueException
          kill_started(started)
          raise
        ensure
          watchers.each(&:join)
        end
        outcomes = watchers.map(&:value)
        failure = outcomes.find { |outcome| outcome.is_a?(Exception) }
        raise failure if failure

        outcomes
      end

      # A watcher that cannot start leaves its child unwatched: reap every
      # child, then report the original error.
      def start_watchers(started, timeout)
        started.map do |part, pid, reader, began|
          Thread.new do
            part.send(:contain, pid, reader, began, timeout, nil)
          rescue Exception => e # rubocop:disable Lint/RescueException
            e
          ensure
            reader.close
          end
        end
      rescue Exception => e # rubocop:disable Lint/RescueException
        reap_started(started)
        raise e
      end

      def kill_started(started)
        started.each do |part, pid, _reader, _began|
          part.send(:signal, "KILL", -pid)
          part.send(:signal, "KILL", pid)
        end
      end

      # Containment for children already forked when a later fork failed:
      # kill every one, then contain each; one child's failure to be
      # contained never leaves a later one running.
      def reap_started(started)
        kill_started(started)
        started.each do |part, pid, reader, began|
          part.send(:contain, pid, reader, began, 0, nil)
        rescue Exception # rubocop:disable Lint/RescueException
          nil
        ensure
          reader.close
        end
      end
    end
  end
end
