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
      # without one), and the subjects that started but stopped mid-list as
      # [subject, omitted_candidate_count] pairs (a spent --max-duration
      # breaking a subject's scheduler loop). unverified lists the subjects
      # whose fresh kills the spent budget left unchecked (#296).
      attr_reader :unreached, :truncated, :unverified

      # The run's peak-memory record for the JSON report (#202): each
      # worker's kernel peak RSS and the supervisor's own, nil when the
      # platform measured neither so the report omits the section. No total:
      # fork copy-on-write makes per-process RSS non-additive.
      def memory_report
        workers = (@pool&.worker_peaks || {}).sort.map { |number, mb| { worker: number, peakMb: mb } }
        supervisor = Execution::PeakMemory.peak_mb
        workers.empty? && supervisor.nil? ? nil : { workers: workers, supervisorPeakMb: supervisor }.compact
      end

      # stop_after: nil, or a callable that gets one subject's results and
      # returns true to stop before the next subject (--fail-fast). It only
      # works on one process: parallel workers have already started the
      # other subjects.
      def initialize(jobs:, scheduler:, diagnostics:, cache:, on_start: nil, after_subject: nil,
                     stop_after: nil, halt_check: nil,
                     drain_timeout: 30) # seconds; two minimum-strength mutant deadlines at default settings
        @jobs = jobs
        @stop_after = stop_after
        @halt_check = halt_check
        @unreached = []
        @truncated = []
        @unverified = []
        @on_start = on_start
        @scheduler = scheduler
        @diagnostics = diagnostics
        @cache = cache
        @after_subject = after_subject
        @drain_timeout = drain_timeout
      end

      # lists: each subject's [[mutation, text]] candidates, in subject order.
      def run(subjects, lists)
        return run_serially(subjects, lists) if @jobs <= 1

        # The watcher runs as each subject's row arrives, before the pool
        # hands out more work, so a tripped canary stops the queue (jobs>1
        # used to check only after the whole batch returned, issue #102).
        # A tool error no longer raises on sight: one wiped log dir hits
        # every worker, and a bystander whose current job ran no mutant
        # reports "an unknown mutant", which could land before the report
        # of the worker whose mutant did the damage (macOS CI on #285).
        # The pool is halted instead - no new work, and the drain is
        # bounded by drain_timeout so a wedged worker cannot stall the
        # abort - and the abort raises the report with the best
        # attribution.
        # The abort reports and the pool are run state: a Distribution
        # runs once. @pool is only read from arrivals, which fire inside
        # @pool.map after the assignment.
        # A budget already spent by boot, baselines or the coverage map
        # launches nothing: every subject comes back unreached (#245).
        if @halt_check&.call
          @unreached = subjects
          return []
        end

        @abort_reports = []
        arrival = arrival_for(subjects, lists)
        @pool = Execution::WorkerPool.new(jobs: @jobs, on_start: @on_start, on_result: arrival,
                                          drain_timeout: @drain_timeout)
        rows = @pool.map(subjects.each_index.to_a, weights: lists.map(&:size)) do |i|
          work(subjects[i], lists[i])
        end
        raise_preferred_tool_error(@abort_reports) if @abort_reports.any?
        record_unreached(rows, subjects, lists)
        rows.each_with_index.flat_map do |row, i|
          next [] if row.nil?

          raise_if_tool_error(row)
          rebuild(row, subjects[i], lists[i])
        end
      end

      private

      # @pool is only read here from arrivals, which fire inside @pool.map
      # after the assignment. A spent --max-duration budget stops the queue
      # without the safety-abort drain: in-flight subjects finish and
      # report, and only never-started ones come back as nil holes, so
      # unreached never mislabels an interrupted subject as unrun (#245).
      def arrival_for(subjects, lists)
        lambda do |i, row|
          if row["tool_error"]
            collect_abort_report(row)
          else
            check_subject(subjects, lists, i, row)
            @pool.halt!(drain: false) if @halt_check&.call
          end
        end
      end

      # nil rows never started; a short results list is a subject whose
      # scheduler stopped mid-list at the budget deadline. Worker-level error
      # rows synthesize an error per candidate, so they never look truncated.
      def unverified_result?(result)
        result.is_a?(MutantResult) && result.status == :unverified && !result.flaky?
      end

      def budget_unverified_row?(result)
        result["status"] == "unverified" && !MutantResult.flaky_reason?(result["reason"])
      end

      def record_unreached(rows, subjects, lists)
        @unreached = []
        @truncated = []
        @unverified = []
        rows.each_with_index do |row, i|
          if row.nil?
            @unreached << subjects[i]
            next
          end
          next unless row["results"] && !row["error"]

          @truncated << [subjects[i], lists[i].size - row["results"].size] if row["results"].size < lists[i].size
          @unverified << subjects[i] if row["results"].any? { |result| budget_unverified_row?(result) }
        end
      end

      # @pool is always assigned when an arrival fires: arrivals only fire
      # from inside @pool.map, which runs after the assignment.
      def collect_abort_report(row)
        @abort_reports << row
        @pool.halt!
      end

      # A canary trip from the end-of-subject check folds into the same
      # record + halt + preferred-report path as a worker's own report:
      # escaping the pool here would override a collected report that
      # names the real culprit (#285 review).
      def check_subject(subjects, lists, index, row)
        @after_subject&.call(subjects[index], decode(row, subjects[index], lists[index]))
      rescue Error => e
        collect_abort_report(Execution::WorkerPool.tool_error_row(e))
      end

      def run_serially(subjects, lists)
        results = []
        subjects.zip(lists).each_with_index do |(subject, list), index|
          # Same pre-dispatch budget check as the parallel first wave: an
          # already-spent baseline starts no further subjects (#245).
          if @halt_check&.call
            @unreached = subjects.drop(index)
            break
          end

          subject_results = @scheduler.call(subject, list)
          results.concat(subject_results)
          # A scheduler that stopped mid-list at the budget deadline: the
          # completed results stay, the omitted candidates are accounted.
          omitted = list.size - subject_results.size
          @truncated << [subject, omitted] if omitted.positive?
          @unverified << subject if subject_results.any? { |result| unverified_result?(result) }
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
          @diagnostics.warn("#{subject.id}: its mutants are reported as errors\n  #{row['error']}")
          return failed(row["error"], subject, list)
        end

        @diagnostics.add_warnings(row["warnings"])
        decode(row, subject, list).each { |result| @cache&.record(result) unless result.reused? }
      end

      # Turns a worker row back into results, without diagnostics or caching:
      # used both at result arrival (the canary) and at rebuild time.
      # A tool error from the worker (a vanished cache dir, ...) aborts
      # the whole run with exit 3; it is not a per-mutant outcome (#283).
      def raise_if_tool_error(row)
        raise Error, row["tool_error"] if row["tool_error"]
      end

      # The abort names a culprit when any report can, ranked by
      # attribution quality (#285 review): a report carrying its mutant's
      # per-mutant digest first, then a canary trip (the hazard report
      # still beats a bare report, #283), then the first bare report.
      def raise_preferred_tool_error(rows)
        row = rows.find { |r| r["culprit"] } || rows.find { |r| r["canary"] } || rows.first
        raise Error, row["tool_error"]
      end

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
