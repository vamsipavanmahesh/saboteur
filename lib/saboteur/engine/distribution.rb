# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Runs each subject's candidates through the scheduler, on one process or
    # on a pool of workers (--jobs N). A worker sends its results back as
    # plain data; the parent rebuilds them against its own copy of the same
    # candidate list, so results look the same either way.
    class Distribution
      # After run: the subjects a stop_after callable left unrun (always empty
      # without one).
      attr_reader :unreached

      # stop_after: nil, or a callable that gets one subject's results and
      # returns true to stop before the next subject (--fail-fast). It only
      # works on one process: parallel workers have already started the
      # other subjects.
      def initialize(jobs:, scheduler:, diagnostics:, cache:, on_start: nil, after_subject: nil,
                     stop_after: nil)
        @jobs = jobs
        @stop_after = stop_after
        @unreached = []
        @on_start = on_start
        @scheduler = scheduler
        @diagnostics = diagnostics
        @cache = cache
        @after_subject = after_subject
      end

      # lists: each subject's [[mutation, text]] candidates, in subject order.
      def run(subjects, lists)
        return run_serially(subjects, lists) if @jobs <= 1

        # The watcher runs as each subject's row arrives, before the pool
        # hands out more work, so a tripped canary stops the queue (jobs>1
        # used to check only after the whole batch returned, issue #102).
        arrival = lambda do |i, row|
          @after_subject&.call(subjects[i], decode(row, subjects[i], lists[i]))
        end
        pool = Execution::WorkerPool.new(jobs: @jobs, on_start: @on_start, on_result: arrival)
        rows = pool.map(subjects.each_index.to_a, weights: lists.map(&:size)) do |i|
          work(subjects[i], lists[i])
        end
        rows.each_with_index.flat_map { |row, i| rebuild(row, subjects[i], lists[i]) }
      end

      private

      def run_serially(subjects, lists)
        results = []
        subjects.zip(lists).each_with_index do |(subject, list), index|
          subject_results = @scheduler.call(subject, list)
          results.concat(subject_results)
          @after_subject&.call(subject, subject_results)
          next unless @stop_after&.call(subject_results)

          @unreached = subjects.drop(index + 1)
          break
        end
        results
      end

      # Runs in a worker.
      def work(subject, list)
        before = @diagnostics.warnings.size
        results = @scheduler.call(subject, list)
        { "warnings" => @diagnostics.warnings.drop(before),
          "results" => results.map { |result| encode(result, list) } }
      end

      def encode(result, list)
        {
          "position" => list.index { |mutation, _| mutation.equal?(result.mutation) },
          "status" => result.status.to_s, "reason" => result.reason, "runtime" => result.runtime,
          "killed_by" => result.killed_by, "covered_by" => result.covered_by,
          "kill_cause" => result.kill_cause, "reused" => result.reused?,
          "rejected_kill" => result.rejected_kill?, "executed" => result.executed
        }
      end

      def rebuild(row, subject, list)
        if row["error"]
          @diagnostics.warn("#{subject.id}: #{row['error']}")
          return failed(row["error"], subject, list)
        end

        @diagnostics.warnings.concat(row["warnings"])
        decode(row, subject, list).each { |result| @cache&.record(result) unless result.reused? }
      end

      # Turns a worker row back into results, without diagnostics or caching:
      # used both at result arrival (the canary) and at rebuild time.
      def decode(row, subject, list)
        return failed(row["error"], subject, list) if row["error"]

        row["results"].map do |data|
          mutation, text = list.fetch(data["position"])
          MutantResult.new(subject: subject, mutation: mutation, status: data["status"].to_sym,
                           mutated_source: text, reason: data["reason"], runtime: data["runtime"],
                           killed_by: data["killed_by"], covered_by: data["covered_by"],
                           kill_cause: data["kill_cause"], reused: data["reused"],
                           executed: data["executed"],
                           rejected_kill: data.fetch("rejected_kill", false))
        end
      end

      # The worker died (or raised) while running this subject.
      def failed(message, subject, list)
        list.map do |mutation, text|
          MutantResult.new(subject: subject, mutation: mutation, status: :error, mutated_source: text,
                           reason: message)
        end
      end
    end
  end
end
