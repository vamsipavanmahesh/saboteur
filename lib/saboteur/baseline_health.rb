# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "tempfile"

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
      raise Error, "baseline has no tests; check rspec_args and spec paths" if expected.empty?

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
      @hooks.run(:before_fork, nil)
      Tempfile.create("saboteur-baseline") do |log|
        result = @supervisor.run(timeout: @config["baseline_timeout"]) { |writer| record(writer, log.path) }
        data = read_result(result, number)
        verify_execution(data, number, expected)
        raise Error, "baseline run #{number} left processes running; fix suite cleanup" if result.leftover_pids.any?

        data["executed"]
      end
    rescue JSON::ParserError
      raise Error, "baseline run #{number} returned an invalid result"
    end

    def read_result(result, number)
      raise Error, "baseline run #{number} stopped: #{result.detail}" if result.stopped_by
      raise Error, "baseline run #{number} exited without a result; check suite boot and exits" if result.payload.empty?
      if result.exit_status.is_a?(Process::Status) && !result.exit_status.success?
        raise Error, "baseline run #{number} exited unsuccessfully; fix suite cleanup and exit handlers"
      end

      data = JSON.parse(result.payload)
      raise Error, "baseline run #{number} returned an invalid result" unless data.is_a?(Hash)

      data
    end

    def verify_execution(data, number, expected)
      unless data["passed"] == true
        raise Error, "baseline run #{number} failed: #{data['error'] || 'fix the unchanged suite'}"
      end
      return if data["executed"].is_a?(Array) && data["executed"].sort == expected.sort

      raise Error, "baseline run #{number} did not execute every requested test; check filters and suite hooks"
    end

    def record(writer, log_path)
      $stdout.reopen(log_path, "w")
      $stderr.reopen($stdout)
      @hooks.run(:after_fork)
      Kernel.srand(@config["seed"])
      ::RSpec.configuration.order = "rand:#{@config['seed']}" if defined?(::RSpec)
      sequence = TestSequence.new
      passed = @integration.run_all(sequence)
      writer.write(JSON.generate(passed: passed, executed: sequence.executed))
    rescue Exception => e # rubocop:disable Lint/RescueException
      writer.write(JSON.generate(passed: false, error: "#{e.class}: #{e.message}"))
    ensure
      writer.close
    end
  end
end
