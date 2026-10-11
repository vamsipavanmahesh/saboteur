# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "fileutils"

module Saboteur
  class Engine
    # Two fresh children check the unchanged suite before any cached verdict
    # or mutation source is used. This catches observed instability, not all
    # possible flaky behaviour.
    class BaselineGuard
      def initialize(config:, integration:, hooks:, supervisor:, diagnostics:)
        @config = config
        @integration = integration
        @hooks = hooks
        @supervisor = supervisor
        @diagnostics = diagnostics
      end

      def call
        expected = @integration.all_tests.map(&:id)
        raise Error, "baseline has no tests. Check rspec_args and the suite filters before running saboteur again." if
          expected.empty?

        @diagnostics.inform("checking the unchanged suite twice (seed #{@config['seed']})")
        previous = nil
        2.times do |index|
          number = index + 1
          data = check(number)
          unless data["passed"] && data["failed"].empty?
            refuse(number,
                   "the suite failed: #{Array(data['failed']).join(', ')}")
          end
          executed = data["executed"]
          refuse(number, "executed tests do not match the loaded suite") unless
            executed.sort == expected.sort
          refuse(number, "test order changed between baseline checks") if previous && executed != previous
          previous = executed
        end
        nil
      end

      private

      def check(number)
        Execution::ForkReadiness.prepare_heap
        result = @diagnostics.with_progress_heartbeat("baseline check #{number}") do
          @supervisor.run(timeout: @config["coverage_timeout"]) { |writer| record(writer, number) }
        end
        refuse(number, "the suite stopped: #{result.stopped_by} (#{result.detail})") if result.stopped_by
        refuse(number, "the child did not report a result") if result.payload.empty?
        refuse(number, "the child exited unsuccessfully") if
          result.exit_status.is_a?(Process::Status) && !result.exit_status.success?
        refuse(number, "the suite left child processes behind") if result.leftover_pids.any?
        parse_result(number, result.payload)
      end

      def parse_result(number, payload)
        data = JSON.parse(payload)
        refuse(number, "the child reported an invalid result") unless data.is_a?(Hash)
        refuse(number, data["error"]) if data["error"]
        refuse(number, "the child reported invalid test results") unless valid_result?(data)
        data
      rescue JSON::ParserError
        refuse(number, "the child reported invalid JSON")
      end

      def valid_result?(data)
        [true, false].include?(data["passed"]) && data["failed"].is_a?(Array) &&
          data["executed"].is_a?(Array) && data["executed"].all?(String)
      end

      def record(writer, number)
        path = log_path(number)
        FileUtils.mkdir_p(File.dirname(path))
        $stdout.reopen(path, "w")
        $stdout.sync = true
        $stderr.reopen($stdout)
        @hooks.run(:after_fork)
        Kernel.srand(@config["seed"])
        result = @integration.run_baseline(seed: @config["seed"])
        writer.write(JSON.generate(passed: result.passed, failed: result.failed_ids, executed: result.executed_ids))
      rescue Exception => e # rubocop:disable Lint/RescueException
        writer.write(JSON.generate(error: "#{e.class}: #{e.message}"))
      ensure
        writer.close
      end

      def log_path(number)
        File.join(@config.path("cache_dir"), "baseline-#{number}.log")
      end

      def refuse(number, reason)
        raise Error, "baseline check #{number} failed at seed #{@config['seed']}: #{reason}. " \
                     "See the log at #{log_path(number)}. Fix the suite or its setup, then run saboteur again " \
                     "with the same seed. No mutants were started."
      end
    end
  end
end
