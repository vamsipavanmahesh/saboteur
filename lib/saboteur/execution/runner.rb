# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "tmpdir"

module Saboteur
  module Execution
    # Runs one subject variant (unchanged or mutated) in a supervised child.
    #
    # The child re-evaluates the method, reports "started", runs the selected
    # tests and reports the result over a pipe. Supervisor owns the child's
    # whole process tree: deadline, memory and process caps, and killing every
    # descendant afterwards, including ones that left the process group.
    class Runner
      # kill_cause: "assertion" when the killing test failed an expectation,
      # else the class of the error it died with (a crash, not a check).
      Outcome = Data.define(:status, :runtime, :failed_ids, :message, :leftover_pids, :kill_cause) do
        def initialize(status:, runtime:, failed_ids: [], message: nil, leftover_pids: [], kill_cause: nil)
          super
        end
      end

      ASSERTION_FAILURES = %w[
        RSpec::Expectations::ExpectationNotMetError
        RSpec::Expectations::MultipleExpectationsNotMetError
        RSpec::Mocks::MockExpectationError
      ].freeze

      # Everything one child needs. mutation is nil for the verdict check.
      Job = Data.define(:subject, :text, :test_ids, :timeout, :mutation, :log_path)

      LOG_TAIL_BYTES = 2000

      def initialize(integration:, reevaluator:, hooks: Hooks.new, log_dir: nil, supervisor: Supervisor.new)
        @integration = integration
        @reevaluator = reevaluator
        @hooks = hooks
        @log_dir = log_dir || Dir.mktmpdir("saboteur-")
        @supervisor = supervisor
      end

      # text: method source to evaluate in the child (the unchanged source for
      # the neutral check). mutation: passed to around_mutant hooks (nil for
      # the neutral check). Returns an Outcome with status
      # :killed, :survived, :timeout, :resource_limit (memory or process cap) or
      # :error.
      def run(subject:, text:, test_ids:, timeout:, mutation: nil)
        @hooks.run(:before_fork, mutation)
        @sequence = @sequence.to_i + 1
        job = Job.new(subject:, text:, test_ids:, timeout:, mutation:,
                      log_path: File.join(@log_dir, "child-#{Process.pid}-#{@sequence}.log"))
        result = @supervisor.run(timeout: timeout) { |writer| child(writer, job) }
        outcome = outcome_for(result, job)
        File.delete(job.log_path) if outcome.status != :error && File.exist?(job.log_path)
        outcome
      end

      private

      # --- child ----------------------------------------------------------

      def child(writer, job)
        Process.setproctitle(title(job))
        redirect_output(job.log_path)
        @hooks.run(:after_fork)
        @reevaluator.call(job.subject, job.text)
        Protocol.emit(writer, "started")
        result = @hooks.around(job.mutation) { run_tests(job.test_ids) }
        if result.nil?
          Protocol.emit(writer, "error", message: "around_mutant hook did not run the tests")
        else
          Protocol.emit(writer, "result", **result)
        end
      rescue Exception => e # rubocop:disable Lint/RescueException
        Protocol.emit(writer, "error", message: "#{e.class}: #{e.message}", backtrace: e.backtrace&.first(5))
        exit!(1)
      end

      # What `ps` shows for this child: which method, and which mutant.
      def title(job)
        "saboteur: #{job.subject.id} #{job.mutation ? job.mutation.operator : 'neutral check'}"
      end

      def run_tests(test_ids)
        result = @integration.run(test_ids)
        { passed: result.passed, failed: result.failed_ids, executed: result.executed_ids, runtime: result.runtime,
          failure_classes: result.failure_classes, failure_messages: result.failure_messages }
      rescue SystemExit => e
        # A test called `exit`. The tests noticed something; count it as a failure.
        { passed: false, failed: [], executed: [], runtime: 0.0, exited: e.status }
      end

      def redirect_output(log_path)
        $stdout.reopen(log_path, "w")
        $stderr.reopen($stdout)
        $stdout.sync = true
        $stderr.sync = true
      end

      # --- parent ---------------------------------------------------------

      def outcome_for(result, job)
        outcome = case result.stopped_by
                  when :timeout
                    Outcome.new(status: :timeout, runtime: result.runtime,
                                message: "exceeded #{job.timeout.round(2)} s")
                  when :memory, :processes
                    Outcome.new(status: :resource_limit, runtime: result.runtime, message: result.detail)
                  else
                    classify(Protocol.parse(result.payload), result.exit_status, result.runtime, job)
                  end
        outcome.with(leftover_pids: result.leftover_pids)
      end

      def classify(events, exit_status, runtime, job)
        started = events.any? { |event| event["event"] == "started" }
        result = events.find { |event| event["event"] == "result" }
        error = events.find { |event| event["event"] == "error" }

        if result
          classify_result(result, runtime, job.test_ids)
        else
          message = if error
                      error["message"]
                    else
                      "child #{describe(exit_status)} #{started ? 'during' : 'before'} tests"
                    end
          message = "#{message} (before tests)" if error && !started
          Outcome.new(status: :error, runtime: runtime, message: [message, log_tail(job.log_path)].compact.join("\n"))
        end
      end

      def classify_result(result, runtime, test_ids)
        failed = Array(result["failed"])
        executed = Array(result["executed"])
        return Outcome.new(status: :killed, runtime: runtime, message: "test called exit") if result.key?("exited")

        if failed.any?
          unexpected = failed - test_ids
          return mismatch(runtime, "failed tests not requested: #{unexpected.first(3).join(', ')}") if unexpected.any?

          return Outcome.new(status: :killed, runtime: runtime, failed_ids: failed,
                             message: result.fetch("failure_messages", {})[failed.first],
                             kill_cause: kill_cause(result.fetch("failure_classes", {})[failed.first]))
        end
        return Outcome.new(status: :killed, runtime: runtime, message: "suite-level failure") unless result["passed"]

        if executed.sort != test_ids.sort
          return mismatch(runtime, "executed #{executed.size} of #{test_ids.size} requested tests")
        end

        Outcome.new(status: :survived, runtime: runtime)
      end

      def kill_cause(failure_class)
        return nil if failure_class.nil?

        ASSERTION_FAILURES.include?(failure_class) ? "assertion" : failure_class
      end

      def mismatch(runtime, message)
        Outcome.new(status: :error, runtime: runtime, message: message)
      end

      def describe(status)
        return "exited" unless status.is_a?(Process::Status)
        return "killed by signal #{status.termsig}" if status.signaled?

        "exited with status #{status.exitstatus}"
      end

      def log_tail(path)
        return nil unless File.exist?(path)

        size = File.size(path)
        return nil if size.zero?

        File.open(path) do |file|
          file.seek([size - LOG_TAIL_BYTES, 0].max)
          file.read.scrub.strip
        end
      end
    end
  end
end
