# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../text"
require_relative "../frameworks/sqlite_memory_database"
require_relative "baseline_parts"

module Saboteur
  class Engine
    # Two fresh children check the unchanged suite before any cached verdict
    # or mutation source is used. This catches observed instability, not all
    # possible flaky behaviour.
    class BaselineGuard
      include BaselineParts

      # How many unchanged-suite checks actually completed and validated:
      # the number of order comparisons a run can claim is one less.
      attr_reader :completed_passes

      EXCERPT_LINES = 10
      EXCERPT_WIDTH = 200
      EXCERPT_SCAN_LINES = 5000

      # full_passes: every full-suite pass the run will make, including the
      # coverage build when the cache is cold, so the first timed pass can
      # price the rest (#260).
      def initialize(config:, integration:, hooks:, supervisor:, diagnostics:, full_passes: 2, between_passes: nil,
                     timeout_cap: nil, run_started: nil)
        @config = config
        @integration = integration
        @hooks = hooks
        @supervisor = supervisor
        @diagnostics = diagnostics
        @full_passes = full_passes
        @between_passes = between_passes
        @timeout_cap = timeout_cap
        @run_started = run_started
        @completed_passes = 0
      end

      def call
        expected = @integration.all_tests.map(&:id)
        raise Error, "baseline has no tests. Check rspec_args and the suite filters before running saboteur again." if
          expected.empty?

        passes = @config["baseline_passes"]
        @diagnostics.detail(announce(passes))
        previous = nil
        passes.times do |index|
          break if budget_spent?(index)

          number = index + 1
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = check(number)
          announce_first_pass_cost(number, started)
          refuse_suite_failure(number, data) unless data["passed"] && data["failed"].empty?
          executed = data["executed"]
          refuse(number, "executed tests do not match the loaded suite") unless
            executed.sort == expected.sort
          refuse(number, "test order changed between baseline checks") if previous && executed != previous
          previous = executed
          @completed_passes += 1
        end
        nil
      end

      private

      def refuse_failed_suite(number, data)
        outside = data["failed"].empty?
        reason = if outside
                   "the suite errored outside any example; see the log tail"
                 else
                   "the suite failed: #{data['failed'].join(', ')}"
                 end
        refuse(number, with_hint(reason, data), tail: outside)
      end

      # A spent --max-duration budget skips the remaining passes - including
      # the first, when boot alone already spent it (#245).
      def budget_spent?(_index)
        !@between_passes.nil? && @between_passes.call
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
      # the remaining full passes cost roughly the same each. full_passes
      # includes the cold-cache coverage build (#260), so name what actually
      # remains: with baseline_passes 1 the one remaining pass is the coverage
      # build, not another baseline check (#465).
      def announce_first_pass_cost(number, started)
        return unless number == 1

        coverage_pending = @full_passes > @config["baseline_passes"]
        remaining = @full_passes - number - (coverage_pending ? 1 : 0)
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round
        warn_budget_projection(elapsed, remaining + (coverage_pending ? 1 : 0))
        return if remaining.zero? && !coverage_pending

        work = []
        work << "the remaining #{remaining} full #{remaining == 1 ? 'pass' : 'passes'}" if remaining.positive?
        work << "the coverage map build" if coverage_pending
        total = remaining + (coverage_pending ? 1 : 0)
        @diagnostics.detail("baseline check #{number} took #{elapsed} s; about #{elapsed * total} s left for " \
                            "#{work.join(' and ')} at that rate")
      end

      # The first timed pass also prices the run against --max-duration:
      # boot and this pass are spent, the remaining passes and a cold
      # coverage build cost about that much again at that rate, and only
      # what is left feeds mutants. Warn while a Ctrl-C is still cheap -
      # the refusal only fires once the coverage build is unaffordable
      # outright (#637).
      def warn_budget_projection(pass_elapsed, remaining_passes)
        budget = @config["max_duration"]
        return unless budget && @run_started

        spent = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @run_started
        projected = spent + (pass_elapsed * remaining_passes)
        mutants_get = budget - projected
        return if mutants_get >= pass_elapsed

        verdict = mutants_get <= 0 ? "exceeds" : "barely fits"
        @diagnostics.warn("raise --max-duration, pass fewer --baseline-passes, or narrow the scope\n  " \
                          "projected baseline+coverage ~#{projected.round}s #{verdict} " \
                          "--max-duration #{budget.round}s; mutants would get " \
                          "~#{format('%g', [mutants_get, 0].max.round(1))}s")
      end

      # An admitted pass still gets only the time left in the run budget:
      # without the cap it would overrun a spent --max-duration by its
      # whole coverage_timeout.
      def phase_timeout
        @timeout_cap ? @timeout_cap.call(@config["coverage_timeout"]) : @config["coverage_timeout"]
      end

      # A pass that hit its deadline only because --max-duration shortened
      # the admission below the configured phase timeout: the budget ended
      # the run, the suite is not broken (#296).
      def budget_stopped?(result, admitted)
        result.stopped_by == :timeout && admitted < @config["coverage_timeout"]
      end

      def refuse_budget_stop(number, admitted)
        raise BudgetPhaseTimeout, "the --max-duration budget stopped baseline check #{number} " \
                                  "(admitted #{admitted.round(1)}s of the #{@config['coverage_timeout']}s " \
                                  "phase timeout)"
      end

      # A containment limit stopping a healthy suite means the limit, not
      # the suite: name the knob and its current value, like the sqlite
      # :memory: hint (#387), so the user is not sent debugging a green
      # suite (#459).
      def stopped_reason(result)
        reason = "the suite stopped: #{result.stopped_by} (#{result.detail})"
        case result.stopped_by
        when :processes
          "#{reason}. If this suite forks heavily by design, raise the limit with " \
          "c.max_processes (currently #{@config['max_processes']})"
        when :memory
          "#{reason}. If this suite legitimately needs more memory, raise the limit with " \
          "c.max_memory_mb (currently #{@config['max_memory_mb']} MB)"
        else
          reason
        end
      end

      def check(number)
        parts = baseline_parts
        return check_parts(number, parts) if parts.size > 1

        Execution::ForkReadiness.prepare_heap
        heartbeat = @diagnostics.progress_heartbeat("baseline check #{number}").watch(log_path(number))
        admitted = phase_timeout
        result = @supervisor.run(timeout: admitted, on_tick: heartbeat.method(:tick),
                                 label: "baseline child died during setup/run") do |writer|
          record(writer, number)
        end
        settled(number, result, admitted)
      end

      def settled(number, result, admitted, part: nil)
        @part = part
        refuse_budget_stop(number, admitted) if budget_stopped?(result, admitted)
        refuse(number, stopped_reason(result)) if result.stopped_by
        # Before the payload checks: a child killed by a signal (the OOM
        # killer, say) writes nothing, and the signal is the explanation. A
        # child the supervisor itself killed after it had reported is not a
        # failure: its payload is checked below.
        refuse(number, unsuccessful_exit(result.exit_status, result.memory_pressure)) if result.child_failed?
        refuse(number, "the child did not report a result") if result.payload.empty?
        refuse(number, leftover_message(result), excerpt: false) if result.leftover_pids.any?
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
        refuse(number, with_hint(data["error"], data)) if data["error"]
        refuse(number, "the child reported invalid test results") unless valid_result?(data)
        data
      rescue JSON::ParserError
        refuse(number, "the child reported invalid JSON")
      end

      def valid_result?(data)
        [true, false].include?(data["passed"]) && data["failed"].is_a?(Array) &&
          data["executed"].is_a?(Array) && data["executed"].all?(String)
      end

      def record(writer, number, files: nil, part: nil)
        path = log_path(number, part)
        FileUtils.mkdir_p(File.dirname(path))
        $stdout.reopen(path, "w")
        $stdout.sync = true
        $stderr.reopen($stdout)
        @hooks.run(:after_fork)
        Kernel.srand(@config["seed"])
        seed = @config["seed"]
        result = files ? @integration.run_baseline(seed: seed, files: files) : @integration.run_baseline(seed: seed)
        payload = { passed: result.passed, failed: result.failed_ids, executed: result.executed_ids }
        payload[:hint] = Frameworks::SqliteMemoryDatabase.fork_loss_hint unless result.passed
        writer.write(JSON.generate(payload))
      rescue Exception => e # rubocop:disable Lint/RescueException
        writer.write(JSON.generate(error: "#{e.class}: #{e.message}",
                                   hint: Frameworks::SqliteMemoryDatabase.fork_loss_hint))
      ensure
        writer.close
      end

      # A failed unchanged suite never runs mutants: warn first when the
      # failure carries the Minitest signature (#626), then refuse.
      def refuse_suite_failure(number, data)
        warn_minitest_signature(number)
        refuse_failed_suite(number, data)
      end

      # Minitest::Spec suites in *_spec.rb clothing load under the RSpec
      # integration and then fail the baseline with NoMethodError for
      # Minitest-only methods (#626): the refusal still reads "fix the
      # suite", so warn what the signature actually points at. It stays a
      # warning: an RSpec suite can require minitest for a helper and
      # fail for its own reason, and a heuristic refusal would
      # false-positive there.
      def warn_minitest_signature(number)
        lines = log_lines(number)
        errors = lines.grep(/NoMethodError/)
        return if errors.empty? || !spec_helper_requires_minitest?

        symptom = (lines.find { |line| line.include?("undefined method") } || errors.first).strip
        @diagnostics.warn("run saboteur on an RSpec suite: it is RSpec-only, so a Minitest suite cannot be " \
                          "mutation tested with it\n  " \
                          "the baseline failure looks like a Minitest suite running under RSpec, not a " \
                          "broken RSpec suite: the log shows #{errors.size} " \
                          "NoMethodError#{'s' if errors.size > 1} (for example: #{symptom.slice(0, EXCERPT_WIDTH)}) " \
                          "and spec/spec_helper.rb requires minitest")
      end

      # The framework check behind the warning: spec_helper is the
      # suite's own declaration of what it runs on. Parsed, not grepped: a
      # regex also fires on commented-out or heredoc "require" lines for a
      # framework the project does not use (#708).
      def spec_helper_requires_minitest?
        require_calls(Prism.parse_file(File.join(@config.root, "spec", "spec_helper.rb")).value)
          .any? { |name| name == "minitest" || name.start_with?("minitest/") }
      rescue SystemCallError
        false
      end

      # Iterative like RefinementActivations.collect: a deeply nested
      # spec_helper must never raise SystemStackError out of a warning
      # heuristic (same class as #711).
      def require_calls(node)
        found = []
        work = [node]
        until work.empty?
          current = work.pop
          next unless current.is_a?(Prism::Node)

          if current.is_a?(Prism::CallNode) && current.name == :require && current.receiver.nil?
            argument = current.arguments&.arguments&.first
            found << argument.unescaped if argument.is_a?(Prism::StringNode)
          end
          work.concat(current.compact_child_nodes)
        end
        found
      end

      # A child that recognises its own failure shape (an empty sqlite
      # :memory: database after the fork, #387) says how to fix it.
      def with_hint(reason, data)
        data["hint"] ? "#{reason}. #{data['hint']}" : reason
      end

      # A split check keeps one log per part: baseline-1-part-2.log.
      def log_path(number, part = @part)
        name = part ? "baseline-#{number}-part-#{part + 1}.log" : "baseline-#{number}.log"
        File.join(@config.path("cache_dir"), name)
      end

      # Leftover children are a pass-with-leaks verdict, not a suite
      # failure: the message names the leaked processes (the supervisor's
      # pre-kill notes) and skips the log excerpt, which holds only RSpec
      # output and can never show them (#486).
      def leftover_message(result)
        notes = result.leftover_notes
        detail = notes.empty? ? result.leftover_pids.join(", ") : notes.join(", ")
        count = result.leftover_pids.size
        "the suite passed but left #{count} child #{count == 1 ? 'process' : 'processes'} behind: #{detail}"
      end

      def refuse(number, reason, excerpt: true, tail: false)
        raise Error, "baseline check #{number} failed at seed #{@config['seed']}: #{reason}. " \
                     "#{failure_excerpt(number, tail: tail) if excerpt}See the full log at #{log_path(number)}. " \
                     "Fix the suite or its setup, then run saboteur again with the same seed. " \
                     "No mutants were started."
      end

      # The first lines of the failure, inline, so the cause is readable
      # without opening the log: RSpec's "Failures:" section when the log has
      # one, otherwise the last lines of the log.
      def failure_excerpt(number, tail: false)
        lines = log_lines(number)
        return "" if lines.empty?

        start = lines.index { |line| line.start_with?("Failures:") } unless tail
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
