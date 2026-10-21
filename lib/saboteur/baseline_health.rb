# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "tempfile"

require_relative "text"

module Saboteur
  # Two fresh supervised children check the full suite without changing methods
  # or writing caches. This samples stability; it cannot prove absence of flakes.
  class BaselineHealth
    class TestSequence
      attr_reader :executed

      def initialize
        @executed = []
      end

      def test_started(_id, _file); end

      def test_finished(id)
        @executed << id
      end
    end

    def initialize(config, integration:, hooks: Hooks.new, supervisor: nil)
      @config = config
      @integration = integration
      @hooks = hooks
      limits = Execution::Supervisor::Limits.new(max_memory_mb: config["max_memory_mb"],
                                                 max_processes: config["max_processes"])
      @supervisor = supervisor || Execution::Supervisor.new(limits: limits)
    end

    def call
      expected = @integration.all_tests.map(&:id)
      if expected.empty?
        raise Error, "baseline has no tests; check rspec_args and the suite filters, " \
                     "then run saboteur doctor --suite again"
      end

      first = check_run(1, expected)
      second = check_run(2, expected)
      if first != second
        raise Error,
              "baseline repeated with different test order; check random ordering and suite setup"
      end

      first
    end

    private

    def check_run(number, expected)
      Tempfile.create("saboteur-baseline") do |log|
        result = @supervisor.run(timeout: @config["baseline_timeout"],
                                 label: "baseline child died during setup/run") { |writer| record(writer, log.path) }
        data = read_result(result, number, log)
        verify_execution(data, number, expected)
        raise Error, "baseline run #{number} left processes running; fix suite cleanup" if result.leftover_pids.any?

        data["executed"]
      end
    rescue JSON::ParserError
      raise Error, "baseline run #{number} returned an invalid result"
    rescue StandardError => e
      raise e if e.is_a?(Error)

      raise Error, "baseline check failed: #{e.class}: #{e.message}; check suite hooks and setup"
    end

    def read_result(result, number, log = nil)
      raise Error, "baseline run #{number} stopped: #{result.detail}" if result.stopped_by
      if result.payload.empty?
        raise Error, "baseline child died during setup/run: baseline run #{number} exited without a " \
                     "result#{exit_detail(result.exit_status)}; check suite boot and exits#{log_tail(log)}"
      end
      if result.child_failed?
        raise Error, "baseline run #{number} exited unsuccessfully; fix suite cleanup and exit handlers"
      end

      data = JSON.parse(result.payload)
      raise Error, "baseline run #{number} returned an invalid result" unless data.is_a?(Hash)

      data
    end

    # The child's own output when it died without answering: the redirect
    # puts its last words in this log, not on the terminal (#289). Bounded
    # (about 2 KB, 20 lines) and scrubbed before it joins the error. Read
    # through the parent's open handle, and strictly best-effort: a dead
    # handle must never mask the real exit or signal error.
    def log_tail(log)
      return "" unless log

      log.seek([log.size - 2048, 0].max)
      tail = Text.utf8(log.read(2048).to_s).lines.last(20).map(&:chomp).join(" / ")
      tail.empty? ? "" : "; child log tail: #{tail}"
    rescue SystemCallError, IOError
      ""
    end

    # The child's ending when the supervisor reaped one ("exit 1",
    # "signal SIGKILL", ...): an empty result's cause is usually there (#255).
    def exit_detail(status)
      return "" unless status.is_a?(Process::Status)
      return " (signal #{Signal.signame(status.termsig)})" if status.signaled?

      " (exit #{status.exitstatus})"
    end

    def verify_execution(data, number, expected)
      unless data["passed"] == true
        raise Error, "baseline run #{number} failed: #{data['error'] || 'fix the unchanged suite'}"
      end
      return if data["executed"].is_a?(Array) && data["executed"].sort == expected.sort

      raise Error, "baseline run #{number} did not execute every requested test; check filters and suite hooks"
    end

    def failure_detail
      return nil unless defined?(::RSpec)

      ::RSpec.world.all_examples.filter_map do |example|
        exception = example.execution_result.exception
        next unless exception

        # Exception text and example names can arrive locale-tagged or as
        # raw path bytes (e.g. Errno::EILSEQ): scrub each field before any
        # strip, truncation or interpolation - all three raise on bad tags.
        # This detail ships in a JSON payload, so it must be valid UTF-8.
        message = Text.utf8(exception.message.to_s).lines.map(&:strip).find { |line| !line.empty? }.to_s[0, 200]
        "#{Text.utf8(example.id.to_s)}: #{Text.utf8(example.full_description.to_s)[0, 200]}: #{message}"
      end.first(5).join("; ")
    end

    def record(writer, log_path)
      $stdout.reopen(log_path, "w")
      $stderr.reopen($stdout)
      @hooks.run(:after_fork)
      Kernel.srand(@config["seed"])
      ::RSpec.configuration.order = "rand:#{@config['seed']}" if defined?(::RSpec)
      sequence = TestSequence.new
      passed = @integration.run_all(sequence)
      writer.write(JSON.generate(passed: passed, executed: sequence.executed, error: failure_detail))
    rescue Exception => e # rubocop:disable Lint/RescueException
      writer.write(JSON.generate(passed: false, error: "#{e.class}: #{e.message}"))
    ensure
      writer.close
    end
  end
end
