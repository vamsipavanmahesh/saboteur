# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require_relative "stale_captures"

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
      # executed_ids: the tests the child reports it ran; empty when it could
      # not say (a test called exit).
      Outcome = Data.define(:status, :runtime, :failed_ids, :message, :leftover_pids, :kill_cause,
                            :executed_ids) do
        def initialize(status:, runtime:, failed_ids: [], message: nil, leftover_pids: [], kill_cause: nil,
                       executed_ids: [])
          super
        end
      end

      ASSERTION_FAILURES = %w[
        RSpec::Expectations::ExpectationNotMetError
        RSpec::Expectations::MultipleExpectationsNotMetError
        RSpec::Mocks::MockExpectationError
      ].freeze

      # Everything one child needs. mutation is nil for the verdict check.
      # eval_prefix: wrapper source (a sorbet sig) evaluated with the def.
      Job = Data.define(:subject, :text, :test_ids, :timeout, :mutation, :log_path, :eval_prefix) do
        def initialize(subject:, text:, test_ids:, timeout:, log_path:, mutation: nil, eval_prefix: nil)
          super
        end
      end

      # The child log (or its whole directory) vanished mid-job (#234).
      # Carries the digest of the mutant whose run just ended when the job
      # had one, so a parallel parent can prefer this report over a
      # bystander's bare "unknown mutant" report (#285).
      class LogVanished < Error
        attr_reader :culprit_digest

        def initialize(message, culprit_digest: nil)
          @culprit_digest = culprit_digest
          super(message)
        end
      end

      LOG_TAIL_BYTES = 2000

      # log_dir: where children write their output; a child's log is kept
      # only when it ends in an error.
      # seed: every child seeds Ruby's random numbers with it before its
      # tests, so a test that uses rand sees the same values in every run.
      # sandbox: when given, a callable run first in every child (Landlock
      # makes the project tree read-only there, #152). It raises rather than
      # run half-restricted, which the child reports as an error.
      def initialize(integration:, reevaluator:, log_dir:, hooks: Hooks.new, supervisor: Supervisor.new, seed: 1,
                     sandbox: nil, canary: nil)
        @integration = integration
        @reevaluator = reevaluator
        @hooks = hooks
        @log_dir = log_dir
        @supervisor = supervisor
        @seed = seed
        @sandbox = sandbox
        @canary = canary
      end

      # text: method source to evaluate in the child (the unchanged source for
      # the neutral check). mutation: passed to around_mutant hooks (nil for
      # the neutral check). Returns an Outcome with status
      # :killed, :survived, :timeout, :resource_limit (memory or process cap) or
      # :error.
      def run(subject:, text:, test_ids:, timeout:, mutation: nil, eval_prefix: nil)
        @hooks.run(:before_fork, mutation)
        @sequence = @sequence.to_i + 1
        job = Job.new(subject:, text:, test_ids:, timeout:, mutation:, eval_prefix:,
                      log_path: File.join(@log_dir, "child-#{Process.pid}-#{@sequence}.log"))
        log_file = open_log(job)
        result = @supervisor.run(timeout: timeout) { |writer| child(writer, job, log_file) }
        outcome = outcome_for(result, job)
        check_tree_still_there(job)
        check_log_still_there(job)
        File.delete(job.log_path) if outcome.status != :error
        outcome
      ensure
        log_file&.close
      end

      private

      # --- child ----------------------------------------------------------

      def child(writer, job, log_file)
        # Redirect before restricting: the sweep closes inherited stdio
        # redirected to a regular file outside the grants (#178), and a
        # reopened-afterwards $stdout would start from a closed stream.
        # The parent opened the log before the fork, so the inherited
        # descriptor survives on the keep list - the cache dir itself
        # stays read-only inside the sandbox (#234). stdio was just
        # reopened onto that log, so 1 and 2 point at a regular file
        # outside the grants and the sweep would close them; keep them
        # explicitly - keeping only the log's own fd is not enough (#283).
        redirect_output(log_file)
        @sandbox&.call([writer.fileno, log_file.fileno, $stdout.fileno, $stderr.fileno])
        Process.setproctitle(title(job))
        @hooks.run(:after_fork)
        # Before the evaluation: a whole-file subject runs the file's own
        # top-level code there, and it must see the run's random numbers.
        Kernel.srand(@seed)
        evaluate_mutant(writer, job)
        stale = stale_captures(job)
        Protocol.emit(writer, "captures", site: stale.first, stale: stale.size) if stale.any?
        Protocol.emit(writer, "started")
        Kernel.srand(@seed)
        emit_result(writer, job, stale.any?)
      rescue Exception => e # rubocop:disable Lint/RescueException
        Protocol.emit(writer, "error", message: "#{e.class}: #{e.message}", backtrace: e.backtrace&.first(5))
        exit!(1)
      end

      def evaluate_mutant(writer, job)
        @reevaluator.call(job.subject, job.text, prefix: job.eval_prefix)
        replaced = @reevaluator.replaced_definition(job.subject)
        Protocol.emit(writer, "replaced", site: replaced) if replaced
      end

      # Capture detection is best-effort: a subject shape it cannot scan
      # must never turn the mutant run itself into an error.
      def stale_captures(job)
        StaleCaptures.scan(@reevaluator, job.subject)
      rescue StandardError
        []
      end

      def emit_result(writer, job, has_captures)
        method = replacement_method(job) if has_captures && job.mutation
        called = method ? false : nil
        trace = TracePoint.new(:call) { called = true } if method
        result = if trace
                   trace.enable(target: method) { @hooks.around(job.mutation) { run_tests(job.test_ids) } }
                 else
                   @hooks.around(job.mutation) { run_tests(job.test_ids) }
                 end
        if result.nil?
          Protocol.emit(writer, "error", message: "around_mutant hook did not run the tests")
        else
          Protocol.emit(writer, "result", **result, replacement_called: called)
        end
      end

      # Targeted tracing distinguishes the new Ruby body from an old Method
      # capture, even though both have the same owner, name and source line.
      def replacement_method(job)
        owner = @reevaluator.resolve_owner(job.subject)
        target = job.subject.singleton ? owner.singleton_class : owner
        method = target.instance_method(job.subject.name)
        Wrapper.original_def(method) || method
      rescue StandardError
        nil
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

      def redirect_output(log_file)
        $stdout.reopen(log_file)
        $stderr.reopen($stdout)
        $stdout.sync = true
        $stderr.sync = true
      end

      # Names the just-run mutant when there is one (a verdict-check rerun
      # has none): the most likely culprit, worth naming for the report.
      def culprit(job)
        culprit_digest(job) || "an unknown mutant"
      end

      # The 16-hex digest of the just-run mutant, or nil when the job ran
      # none (a neutral or verdict-check rerun): a parallel parent prefers
      # the vanished-log report that carries one (#285).
      def culprit_digest(job)
        return unless job.mutation && job.subject.respond_to?(:start_byte)

        job.mutation.digest(subject_start: job.subject.start_byte,
                            original_source: job.subject.file_source)
      end

      # Opened in the parent, not the sandboxed child: the cache dir is
      # not writable inside the sandbox (#234), and a log directory that
      # is already gone is a tool problem to report, not a mutant result.
      def open_log(job)
        File.open(job.log_path, "w")
      rescue SystemCallError => e
        raise Error, "cannot open the child log #{job.log_path} (#{e.class}: #{e.message})"
      end

      # A mutant's tests can delete saboteur's own files when the sandbox
      # is off or degraded (#234): a vanished log makes the verdict
      # worthless, so fail as a tool error instead of trusting the run.
      # The mutant that just ran is the likely - not proven - cause: a
      # leftover process from an earlier mutant could have done it.
      # The per-mutant probe (#235): names the mutant whose run just wiped
      # tracked files, instead of blaming the subject's last mutant when the
      # loss surfaces at subject end. Runs before the log check, so the
      # hazard report still wins when a mutant took both (#283).
      def check_tree_still_there(job)
        # culprit_digest, not the display fallback: the digest doubles as
        # trip metadata, and "an unknown mutant" must not rank as one (#285).
        @canary&.probe!(subject: job.subject, digest: culprit_digest(job))
      end

      def check_log_still_there(job)
        return if File.exist?(job.log_path)

        cause = "a mutant's tests may have hit saboteur's files"
        raise LogVanished.new("the child log #{job.log_path} vanished mid-run - the mutant that just ran, " \
                              "#{culprit(job)}, is the likely cause: #{cause}",
                              culprit_digest: culprit_digest(job))
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
          classify_events(result, events, runtime, job)
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

          return Outcome.new(status: :killed, runtime: runtime, failed_ids: failed, executed_ids: executed,
                             message: result.fetch("failure_messages", {})[failed.first],
                             kill_cause: kill_cause(result.fetch("failure_classes", {})[failed.first]))
        end
        unless result["passed"]
          return Outcome.new(status: :killed, runtime: runtime, executed_ids: executed,
                             message: "suite-level failure")
        end

        if executed.sort != test_ids.sort
          return mismatch(runtime, "executed #{executed.size} of #{test_ids.size} requested tests")
        end

        Outcome.new(status: :survived, runtime: runtime, executed_ids: executed)
      end

      def classify_events(result, events, runtime, job)
        outcome = classify_result(result, runtime, job.test_ids)
        replaced = events.find { |event| event["event"] == "replaced" }
        return replaced_by_later_definition(outcome, replaced) if never_ran?(outcome, replaced, job)

        captures = events.find { |event| event["event"] == "captures" }
        return unreachable(outcome, captures) if unobservable?(outcome, captures, job, result["replacement_called"])

        outcome
      end

      # A surviving mutant whose definition a later one in the same file
      # replaced: the tests could not have run it, so it is no verdict on them.
      def never_ran?(outcome, replaced, job)
        replaced && job.mutation && outcome.status == :survived
      end

      def replaced_by_later_definition(outcome, replaced)
        Outcome.new(status: :unreachable, runtime: outcome.runtime,
                    message: "the whole-file evaluation left another definition in place " \
                             "(#{replaced['site']}), so this mutant never ran")
      end

      # Only mutant runs convert: the verdict check re-evaluates the
      # unchanged method, and a stale capture there must not overturn a real
      # kill.
      def unobservable?(outcome, captures, job, replacement_called)
        captures && job.mutation && outcome.status == :survived && replacement_called == false
      end

      # A survivor that no test could have observed: a Method object
      # captured at load still calls the original. Not a verdict on the
      # tests, so it is its own status, out of the score.
      def unreachable(outcome, captures)
        Outcome.new(status: :unreachable, runtime: outcome.runtime,
                    message: "a Method object captured before re-evaluation still calls the original " \
                             "(captured definition at #{captures['site']})")
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
