# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../text"

module Saboteur
  class Engine
    # Two fresh children check the unchanged suite before any cached verdict
    # or mutation source is used. This catches observed instability, not all
    # possible flaky behaviour.
    class BaselineGuard
      EXCERPT_LINES = 10
      EXCERPT_WIDTH = 200
      EXCERPT_SCAN_LINES = 5000

      # full_passes: every full-suite pass the run will make, including the
      # coverage build when the cache is cold, so the first timed pass can
      # price the rest (#260).
      def initialize(config:, integration:, hooks:, supervisor:, diagnostics:, full_passes: 2, between_passes: nil)
        @config = config
        @integration = integration
        @hooks = hooks
        @supervisor = supervisor
        @diagnostics = diagnostics
        @full_passes = full_passes
        @between_passes = between_passes
      end

      def call
        expected = @integration.all_tests.map(&:id)
        raise Error, "baseline has no tests. Check rspec_args and the suite filters before running saboteur again." if
          expected.empty?

        passes = @config["baseline_passes"]
        @diagnostics.inform(announce(passes))
        previous = nil
        passes.times do |index|
          break if budget_spent?(index)

          number = index + 1
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = check(number)
          announce_first_pass_cost(number, started)
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

      # A spent --max-duration budget skips the remaining passes: the
      # pre-dispatch check stops the run before any subject anyway.
      def budget_spent?(index)
        index.positive? && @between_passes&.call
      end

      def announce(passes)
        case passes
        when 1
          "checking the unchanged suite once (seed #{@config['seed']}); " \
          "order stability between passes is not checked (baseline_passes: 1)"
        when 2
          "checking the unchanged suite twice (seed #{@config['seed']})"
        else
          "checking the unchanged suite #{passes} times (seed #{@config['seed']})"
        end
      end

      # Once the first pass is timed, the total cost stops being a guess:
      # the remaining full passes cost roughly the same each.
      def announce_first_pass_cost(number, started)
        return unless number == 1

        remaining = @full_passes - number
        return if remaining.zero?

        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round
        @diagnostics.inform("baseline check #{number} took #{elapsed} s; about #{elapsed * remaining} s left for " \
                            "the remaining #{remaining} full #{remaining == 1 ? 'pass' : 'passes'} at that rate")
      end

      def check(number)
        Execution::ForkReadiness.prepare_heap
        heartbeat = @diagnostics.progress_heartbeat("baseline check #{number}").watch(log_path(number))
        result = @supervisor.run(timeout: @config["coverage_timeout"], on_tick: heartbeat.method(:tick),
                                 label: "baseline child died during setup/run") do |writer|
          record(writer, number)
        end
        refuse(number, "the suite stopped: #{result.stopped_by} (#{result.detail})") if result.stopped_by
        # Before the payload checks: a child killed by a signal (the OOM
        # killer, say) writes nothing, and the signal is the explanation. A
        # child the supervisor itself killed after it had reported is not a
        # failure: its payload is checked below.
        refuse(number, unsuccessful_exit(result.exit_status, result.memory_pressure)) if result.child_failed?
        refuse(number, "the child did not report a result") if result.payload.empty?
        refuse(number, "the suite left child processes behind") if result.leftover_pids.any?
        parse_result(number, result.payload)
      end

      # A signaled child (the OOM killer, say) can leave an empty log,
      # which reads like a suite failure; name the signal. The OOM hint is
      # printed only when the supervisor saw the process tree's memory grow.
      def unsuccessful_exit(status, memory_pressure)
        return "the child exited with status #{status.exitstatus}" unless status.signaled?

        signal = "SIG#{Signal.signame(status.termsig)}"
        hint = signal == "SIGKILL" && memory_pressure ? " - possible OOM, check memory" : ""
        "the child was killed by #{signal}#{hint}"
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
                     "#{failure_excerpt(number)}See the full log at #{log_path(number)}. Fix the suite or its " \
                     "setup, then run saboteur again with the same seed. No mutants were started."
      end

      # The first lines of the failure, inline, so the cause is readable
      # without opening the log: RSpec's "Failures:" section when the log has
      # one, otherwise the last lines of the log.
      def failure_excerpt(number)
        lines = log_lines(number)
        return "" if lines.empty?

        start = lines.index { |line| line.start_with?("Failures:") }
        shown = start ? lines[start, EXCERPT_LINES] : lines.last(EXCERPT_LINES)
        "The log says:\n#{shown.map { |line| "  #{line.slice(0, EXCERPT_WIDTH)}" }.join("\n")}\n"
      end

      def log_lines(number)
        File.foreach(log_path(number), chomp: true).first(EXCERPT_SCAN_LINES)
            .map { |line| Text.utf8(line) }.reject { |line| line.strip.empty? }
      rescue SystemCallError
        []
      end
    end
  end
end
