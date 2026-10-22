# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require_relative "stale_captures"
require_relative "../crash_report"

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
      CRASH_LOG_BYTES = 2_000
      CRASH_LOG_LINES = 8
      # File mtimes follow the filesystem's clock, which can trail the
      # process clock; a log written during this run can stamp a little
      # before its start, so the freshness check allows that skew.
      CRASH_LOG_CLOCK_SLACK = 2
      # Freshness matching can attach another run's log (clock slack, two
      # nested runs in one child), so the label must not claim exact
      # attribution (#296).
      CRASH_LOG_LABEL = "recent saboteur crash log (freshness-matched, may be another run's):"

      # log_dir: where children write their output; a child's log is kept
      # only when it ends in an error. crash_log: the crash log of a saboteur
      # run nested inside a test; by default it sits next to the logs dir,
      # where the engine's cache dir keeps it.
      # seed: every child seeds Ruby's random numbers with it before its
      # tests, so a test that uses rand sees the same values in every run.
      # sandbox: when given, a callable run first in every child (Landlock
      # makes the project tree read-only there, #152). It raises rather than
      # run half-restricted, which the child reports as an error.
      # Survivor confirmation loads the spec files a scoped run left out (#1286).
      attr_reader :integration

      def initialize(integration:, reevaluator:, log_dir:, hooks: Hooks.new, supervisor: Supervisor.new, seed: 1,
                     sandbox: nil, canary: nil, crash_log: nil)
        @integration = integration
        @reevaluator = reevaluator
        @hooks = hooks
        @log_dir = log_dir
        @supervisor = supervisor
        @seed = seed
        @sandbox = sandbox
        @canary = canary
        @crash_log = crash_log || File.join(File.dirname(log_dir), CrashReport::LOG_NAME)
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
        @installed_definition = job.mutation ? @reevaluator.installed_definition(job.subject) : nil
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
        flags = { replacement_called: method ? false : nil, mutant_called: false }
        target = method || (job.mutation ? @installed_definition : nil)
        trace = call_probe(target, flags)
        started_at = Time.now
        suite = proc { @hooks.around(job.mutation) { run_tests(job.test_ids) } }
        result = trace ? trace.enable(target: target, &suite) : suite.call
        if result.nil?
          Protocol.emit(writer, "error", message: "around_mutant hook did not run the tests")
        else
          called = flags[:replacement_called]
          Protocol.emit(writer, "result", **with_crash_detail(result, started_at), replacement_called: called)
          # A reload after the mutant already ran (an after-hook restore)
          # is no reason to doubt the verdict; only a never-invoked mutant
          # can have been hidden by the overwrite.
          emit_overwritten(writer, job, flags[:mutant_called])
        end
      end

      # A reload after the mutant already ran (an after-hook restore) is
      # no reason to doubt the verdict; only a never-invoked mutant can
      # have been hidden by the overwrite.
      def emit_overwritten(writer, job, mutant_called)
        overwritten = job.mutation && @installed_definition &&
                      @reevaluator.overwritten_site(job.subject, @installed_definition)
        Protocol.emit(writer, "overwritten", site: overwritten) if overwritten && !mutant_called
      end

      # One call probe on the installed definition feeds both verdicts:
      # replacement_called for stale captures, and overwrite detection for
      # a mutant the suite replaced before any test ran it (#597).
      def call_probe(target, flags)
        target && TracePoint.new(:call) do
          flags[:mutant_called] = true
          flags[:replacement_called] = true unless flags[:replacement_called].nil?
        end
      end

      # A test can run saboteur itself (the dogfood's cli_spec): the nested
      # CLI reports its own crashes as exit 3 and logs them to
      # internal-error.log. A log written during this run explains the
      # failure better than the bare expectation diff, so its first lines
      # join each failure detail; an older log is another run's (#296).
      def with_crash_detail(result, started_at)
        excerpt = crash_log_excerpt(started_at)
        details = result[:failure_details]
        return result unless excerpt && details && !details.empty?

        result.merge(failure_details: details.transform_values { |d| [d, CRASH_LOG_LABEL, excerpt].join("\n") })
      end

      # The nested CLI writes its log to the cache dir, or to the pid-keyed
      # temp fallback when the sandbox holds the cache dir read-only (#296).
      def crash_log_excerpt(started_at)
        excerpt = tmp_log_candidates.filter_map { |path| fresh_log_excerpt(path, started_at) }
                                    .max_by { |mtime, _text| mtime }
        excerpt&.last
      rescue StandardError
        nil
      end

      # The log paths are predictable and live in shared dirs, so read the
      # log the way CrashReport writes it: through a no-follow, non-blocking
      # descriptor,
      # and validate on that same fd - a regular file, owned by this uid,
      # with no group/other permission bits, fresh by the fd's own mtime.
      # One open, no check-then-reopen race; a symlink, a foreign, wide or
      # non-regular file, or any IO failure is no excerpt, never an
      # exception (#296).
      def fresh_log_excerpt(path, started_at)
        # No safe open, no excerpt: without O_NOFOLLOW a symlink redirects
        # the read, without O_NONBLOCK a no-writer FIFO blocks it (#296).
        return unless CrashReport.safe_log_io?

        flags = File::RDONLY | CrashReport.nofollow_flag | CrashReport.nonblock_flag
        File.open(path, flags) do |file|
          stat = file.stat
          next unless stat.file? && stat.uid == Process.uid && stat.mode.nobits?(0o077)
          next unless stat.mtime >= started_at - CRASH_LOG_CLOCK_SLACK

          text = file.read(CRASH_LOG_BYTES)
          # Scrub before the excerpt travels as JSON: the bounded read can
          # end mid-character and the log can hold locale-invalid bytes, and
          # a JSON::GeneratorError here would turn a kill into a child error
          # (#296).
          [stat.mtime, text ? CrashReport.scrub(text).lines.first(CRASH_LOG_LINES).join : nil]
        end
      rescue SystemCallError, IOError
        nil
      end

      # The excerpt is diagnostic enrichment: when CrashReport itself is the
      # mutated file, tmp_log_path can raise or return garbage - keep the
      # primary candidate and never let the lookup change a verdict (#296).
      def tmp_log_candidates
        [@crash_log, CrashReport.tmp_log_path].compact.uniq.grep(String)
      rescue StandardError
        [@crash_log].compact
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
          failure_classes: result.failure_classes, failure_messages: result.failure_messages,
          failure_details: result.failure_details }
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

      def classify_result(result, runtime, test_ids, verbose_failure: false)
        failed = Array(result["failed"])
        executed = Array(result["executed"])
        return Outcome.new(status: :killed, runtime: runtime, message: "test called exit") if result.key?("exited")

        if failed.any?
          unexpected = failed - test_ids
          return mismatch(runtime, "failed tests not requested: #{unexpected.first(3).join(', ')}") if unexpected.any?

          return killed_outcome(result, runtime, failed, executed, verbose_failure)
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

      def killed_outcome(result, runtime, failed, executed, verbose_failure)
        Outcome.new(status: :killed, runtime: runtime, failed_ids: failed, executed_ids: executed,
                    message: failure_message(result, failed.first, verbose_failure),
                    kill_cause: kill_cause(result.fetch("failure_classes", {})[failed.first]))
      end

      # A neutral check (the verdict re-run, no mutation) needs the full
      # failure to explain why the killer fails unchanged (#296).
      def failure_message(result, test_id, verbose_failure)
        message = result.fetch("failure_messages", {})[test_id]
        verbose_failure ? result.fetch("failure_details", {})[test_id] || message : message
      end

      def classify_events(result, events, runtime, job)
        outcome = classify_result(result, runtime, job.test_ids, verbose_failure: job.mutation.nil?)
        replaced = events.find { |event| event["event"] == "replaced" }
        return replaced_by_later_definition(outcome, replaced) if never_ran?(outcome, replaced, job)

        captures = events.find { |event| event["event"] == "captures" }
        return unreachable(outcome, captures) if unobservable?(outcome, captures, job, result["replacement_called"])

        overwritten = events.find { |event| event["event"] == "overwritten" }
        return overwritten_by_later_load(outcome, overwritten) if replaced_while_running?(outcome, overwritten, job)

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

      # A surviving mutant the tests themselves overwrote: a before(:each)
      # re-loading the file replaced it before any test ran (rolify's suite
      # shape, #597), so the verdict says nothing about the tests.
      def replaced_while_running?(outcome, overwritten, job)
        overwritten && job.mutation && outcome.status == :survived
      end

      def overwritten_by_later_load(outcome, overwritten)
        Outcome.new(status: :unreachable, runtime: outcome.runtime,
                    message: "the tests (or their hooks) replaced the definition while they ran " \
                             "(#{overwritten['site']}), so this mutant never ran")
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
