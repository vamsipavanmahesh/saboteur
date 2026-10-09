# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "tmpdir"

module Saboteur
  # Runs one subject variant (unchanged or mutated) in a forked child.
  #
  # The child puts itself in its own process group, re-evaluates the method,
  # reports "started", runs the selected tests and reports the result over a
  # pipe. The parent enforces the deadline and always kills the whole group
  # afterwards, so grandchildren (servers, subprocesses) do not outlive it.
  class Runner
    Outcome = Data.define(:status, :runtime, :failed_ids, :message) do
      def initialize(status:, runtime:, failed_ids: [], message: nil)
        super
      end
    end

    # Everything one child needs. mutation is nil for the neutral check.
    Job = Data.define(:subject, :text, :test_ids, :timeout, :mutation, :log_path)

    TERM_GRACE = 1.0
    LOG_TAIL_BYTES = 2000

    def initialize(integration:, reevaluator:, hooks: Hooks.new, log_dir: nil)
      @integration = integration
      @reevaluator = reevaluator
      @hooks = hooks
      @log_dir = log_dir || Dir.mktmpdir("saboteur-")
      @live = Set.new
      install_cleanup
    end

    # text: method source to evaluate in the child (the unchanged source for
    # the neutral check). mutation: passed to around_mutant hooks (nil for
    # the neutral check). Returns an Outcome with status
    # :killed, :survived, :timeout or :error.
    def run(subject:, text:, test_ids:, timeout:, mutation: nil)
      @hooks.run(:before_fork, mutation)
      @sequence = @sequence.to_i + 1
      job = Job.new(subject:, text:, test_ids:, timeout:, mutation:,
                    log_path: File.join(@log_dir, "child-#{Process.pid}-#{@sequence}.log"))
      reader, writer = IO.pipe
      $stdout.flush
      $stderr.flush
      started_at = monotonic
      pid = fork { child(reader, writer, job) }
      writer.close
      track(pid)
      outcome = supervise(pid, reader, started_at, job)
      File.delete(job.log_path) if outcome.status != :error && File.exist?(job.log_path)
      outcome
    ensure
      reader&.close unless reader&.closed?
    end

    private

    # --- child ----------------------------------------------------------

    def child(reader, writer, job)
      reader.close
      Process.setpgid(0, 0)
      trap("TERM") { exit!(143) }
      redirect_output(job.log_path)
      @hooks.run(:after_fork)
      @reevaluator.call(job.subject, job.text)
      emit(writer, event: "started")
      result = @hooks.around(job.mutation) { run_tests(job.test_ids) }
      if result.nil?
        emit(writer, event: "error", message: "around_mutant hook did not run the tests")
      else
        emit(writer, event: "result", **result)
      end
      exit!(0)
    rescue Exception => e # rubocop:disable Lint/RescueException
      emit(writer, event: "error", message: "#{e.class}: #{e.message}", backtrace: e.backtrace&.first(5))
      exit!(1)
    end

    def run_tests(test_ids)
      result = @integration.run(test_ids)
      { passed: result.passed, failed: result.failed_ids, executed: result.executed_ids, runtime: result.runtime }
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

    def emit(writer, payload)
      writer.write("#{JSON.generate(payload)}\n")
      writer.flush
    rescue IOError, SystemCallError
      nil
    end

    # --- parent ---------------------------------------------------------

    def supervise(pid, reader, started_at, job)
      events = read_events(reader, started_at + job.timeout)
      timed_out = events.equal?(:timeout)
      status = kill_group(pid, gracefully: timed_out)
      runtime = monotonic - started_at
      return Outcome.new(status: :timeout, runtime: runtime, message: "exceeded #{job.timeout.round(2)} s") if timed_out

      classify(events, status, runtime, job)
    end

    # Returns the list of events, or :timeout if the deadline passed first.
    def read_events(reader, deadline)
      buffer = +""
      loop do
        remaining = deadline - monotonic
        return :timeout if remaining <= 0
        next unless reader.wait_readable(remaining)

        chunk = reader.read_nonblock(65_536, exception: false)
        break if chunk.nil?
        next if chunk == :wait_readable

        buffer << chunk
      end
      buffer.each_line.filter_map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
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

        return Outcome.new(status: :killed, runtime: runtime, failed_ids: failed)
      end
      return Outcome.new(status: :killed, runtime: runtime, message: "suite-level failure") unless result["passed"]

      if executed.sort != test_ids.sort
        return mismatch(runtime, "executed #{executed.size} of #{test_ids.size} requested tests")
      end

      Outcome.new(status: :survived, runtime: runtime)
    end

    def mismatch(runtime, message)
      Outcome.new(status: :error, runtime: runtime, message: message)
    end

    # Kills the child's process group and reaps the child. With gracefully,
    # sends TERM first and waits up to TERM_GRACE seconds.
    def kill_group(pid, gracefully:)
      status = nil
      if gracefully
        signal_group(pid, "TERM")
        deadline = monotonic + TERM_GRACE
        until (status = reap(pid, Process::WNOHANG)) || monotonic > deadline
          sleep 0.01
        end
      end
      status ||= reap(pid, Process::WNOHANG)
      signal_group(pid, "KILL")
      status ||= reap(pid, 0)
      @live.delete(pid)
      status
    end

    def signal_group(pid, signal)
      Process.kill(signal, -pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def reap(pid, flags)
      _, status = Process.waitpid2(pid, flags)
      status
    rescue Errno::ECHILD
      :reaped
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

    def track(pid)
      @live << pid
      # The child may not have called setpgid yet; do it from the parent too
      # so a kill right after fork still reaches the group.
      Process.setpgid(pid, pid)
    rescue Errno::EACCES, Errno::ESRCH, Errno::EPERM
      nil
    end

    def install_cleanup
      live = @live
      parent = Process.pid
      at_exit do
        next unless Process.pid == parent

        live.each do |pid|
          Process.kill("KILL", -pid)
        rescue Errno::ESRCH, Errno::EPERM
          nil
        end
      end
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
