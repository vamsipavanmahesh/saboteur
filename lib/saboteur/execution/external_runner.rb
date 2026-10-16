# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "find"
require "pathname"
require "tmpdir"

module Saboteur
  module Execution
    # Runs mutants through a user-supplied shell command (#140): each
    # execution gets a FRESH disposable copy of the project tree, so every
    # mutant and every neutral check starts from a pristine snapshot and a
    # destructive command cannot poison later runs. The mutant is written
    # into the copy - never the real file; the runner's own writes never
    # follow symlinks and never leave the copy - and the command runs there
    # with the caller's permissions: unsandboxed, with network and side
    # effects exactly as if typed into a shell, including writing anywhere
    # it chooses by absolute path. Its exit status decides the verdict: 0
    # survived, non-zero killed (except the shell's 126/127 and signals,
    # which read as command/setup errors), deadline timeout. It is the mode
    # for target apps that cannot load inside this Ruby (apps on older
    # Rubies); it is explicitly slower, now also one tree copy per
    # execution.
    #
    # Safety shape, stated narrowly: the pristine reference is the real
    # tree itself, read per subject as subject.file_source; the copy is
    # not a canary and proves nothing by itself. Because only the copy is
    # mutated, a failed write or a command that keeps writing in the
    # background hits the copy, not the checkout; the command can still
    # write anywhere else by absolute path, so only trusted commands
    # belong here. The command's whole process group is TERM/KILLed and
    # reaped in an ensure on every exit path (verdict, timeout, error,
    # interrupt); a SIGKILL of this process can leave the group alive.
    # Output capture is bounded as it is written (a ring buffer), so a
    # chatty command cannot fill memory or disk. A neutral preflight runs
    # the command once on an untouched copy before any mutant exists, so a
    # typo command fails immediately with its own output.
    class ExternalRunner
      # The command is one test in the report's eyes: a kill names it as
      # the killer, a run lists it as executed.
      PSEUDO_TEST = "(test command)"

      # Shell "cannot execute" / "command not found" read as setup errors,
      # never as kills: the suite did not run.
      SETUP_EXIT_CODES = [126, 127].freeze

      # The child inherits this marker and Boot.refuse_recursion! refuses
      # any saboteur run inside it, so a test command that itself invokes
      # saboteur cannot mutate the copy mid-run.
      CHILD_MARKER = "SABOTEUR_EXTERNAL_CHILD"

      # Bounded capture: only the last bytes of combined output are kept,
      # for preflight and error messages.
      OUTPUT_LIMIT = 64 * 1024

      # Grace for the capture drain after the command exits: a descendant
      # holding the pipe past this no longer blocks the run.
      DRAIN_GRACE = 0.5

      def initialize(command:, root:)
        @command = command
        # realpath, not expand_path: the tree must be judged by where it
        # really is, so a subject path can be checked against the same
        # canonical root without a symlink making it look outside (#305 QA).
        @root = File.realpath(root)
        @copy_root = nil
        at_exit { close }
      rescue SystemCallError
        raise Error, "the test command root does not exist: #{root}"
      end

      # Runs the command once on an untouched copy before any mutant
      # exists. A failing command can never claim kills, so fail the whole
      # run here with the command's own output (#140, #305).
      # deadline is absolute (CLOCK_MONOTONIC): the copy is made first and
      # the command is admitted only with the time then remaining, so the
      # copy can never eat the budget while the command still gets its full
      # slice (#305 Architect). An already-spent deadline is a budget stop,
      # not a command failure.
      def preflight!(deadline: monotonic + 60)
        result = with_fresh_copy do
          remaining = deadline - monotonic
          raise BudgetPhaseTimeout, "the --max-duration budget stopped the external preflight" if remaining <= 0

          spawn_and_wait(remaining)
        end
        case result
        when 0 then true
        when Exception
          raise Error, "the test command could not be started: #{result.message}"
        else
          raise Error, "the test command fails on the unchanged tree " \
                       "(#{describe_exit(result)}):\n#{last_output}"
        end
      end

      # Same contract as Runner#run. text, test_ids and eval_prefix belong
      # to the in-process machinery and are ignored here. The neutral run
      # (mutation nil) writes the unchanged bytes explicitly: every
      # execution proves the write path against pristine content (#305).
      def run(subject:, text:, test_ids:, timeout:, mutation: nil, eval_prefix: nil) # rubocop:disable Lint/UnusedMethodArgument
        started = monotonic
        message = nil
        status = begin
          with_fresh_copy do
            write_subject(subject, mutation)
            verdict_for(spawn_and_wait(timeout))
          end
        # A copy or write failure is this execution's outcome, never a crash
        # of the run: report it with bounded context like any command error
        # (#305 QA).
        rescue Error, SystemCallError => e
          message = bounded(e.message)
          :error
        end
        Runner::Outcome.new(status: status, runtime: monotonic - started,
                            failed_ids: status == :killed ? [PSEUDO_TEST] : [],
                            executed_ids: status == :error ? [] : [PSEUDO_TEST],
                            message: message || (status == :error ? error_context : nil))
      end

      # Drops the current disposable copy. Public so the engine can release
      # the tree as soon as the run ends; idempotent, and the at_exit
      # backstop calls it again.
      def close
        FileUtils.rm_rf(@copy_root) if @copy_root
        @copy_root = nil
      rescue SystemCallError
        nil
      end

      private

      # A pristine copy of the tree for one execution (#305 QA/DevRel): the
      # previous execution's copy - mutated file, command side effects and
      # all - is dropped before the new one is made.
      def with_fresh_copy
        close
        @copy_root = Dir.mktmpdir("saboteur-external-")
        FileUtils.cp_r(File.join(@root, "."), @copy_root, preserve: true)
        rebuild_symlinks
        yield
      end

      # cp_r keeps symlinks, and a write through a link that escapes the
      # copy would land in the real tree. Links resolving inside the tree
      # are REBUILT as relative links inside the copy: alias identity is
      # preserved, so requiring the alias sees the same (possibly mutated)
      # content as the real path, and the link can never point out (#305
      # QA). Chains collapse to the final target, which is equivalent.
      # Anything escaping the tree or unresolvable refuses the run.
      def rebuild_symlinks
        Find.find(@copy_root) do |path|
          next unless File.symlink?(path)

          target = File.realpath(path)
          unless target.start_with?("#{@copy_root}/")
            raise Error, "the tree links outside itself: #{path.sub("#{@copy_root}/", '')} -> #{target}; " \
                         "external test commands need a self-contained tree"
          end

          relative = Pathname.new(target).relative_path_from(Pathname.new(File.dirname(path))).to_s
          File.unlink(path)
          File.symlink(relative, path)
        rescue SystemCallError
          raise Error, "unresolvable symlink in the tree: #{path.sub("#{@copy_root}/", '')}"
        end
      end

      # The mutation's edits apply at absolute byte offsets in the file;
      # the neutral run writes the original bytes back. The reference text
      # is the real tree's, never the copy's (#305 DevRel canary).
      def write_subject(subject, mutation)
        path = File.join(@copy_root, relative(subject))
        File.binwrite(path, mutation ? mutated_source(subject, mutation) : subject.file_source)
      end

      # The subject must live under the canonical root; anything else -
      # absolute or `..` traversal - is refused, never joined onto the copy
      # (#305 QA).
      def relative(subject)
        expanded = File.expand_path(subject.file)
        prefix = "#{@root}/"
        raise Error, "the subject file is outside the project root: #{subject.file}" unless expanded.start_with?(prefix)

        expanded[prefix.length..]
      end

      def mutated_source(subject, mutation)
        source = subject.file_source.dup.b
        mutation.edits.sort_by(&:start_byte).reverse_each do |edit|
          source = source.byteslice(0, edit.start_byte) + edit.replacement.b + source.byteslice(edit.end_byte..)
        end
        source.force_encoding(Encoding::UTF_8)
      end

      def verdict_for(result)
        case result
        when :timeout then :timeout
        when Exception, :signal, *SETUP_EXIT_CODES then :error
        when 0 then :survived
        else :killed
        end
      end

      def error_context
        "#{describe_exit(@last_result)}: #{last_output}"
      end

      def spawn_and_wait(timeout)
        # Always through the shell: users write pipelines and redirects,
        # and a bare unknown word must exit 127 instead of raising ENOENT.
        start_capture
        pid = spawn_shell
        # The parent's copy of the write end closes right after the spawn:
        # while it stays open the reader never sees EOF and the drain below
        # would always wait out its grace (#305 Architect).
        @capture_writer.close
        @capture_writer = nil
        @last_result = await_exit(pid, timeout)
      rescue SystemCallError => e
        @last_result = e
      ensure
        # The whole process group goes down on every exit path - verdict,
        # timeout, error and interrupt alike - so background descendants
        # cannot write after the verdict is in (#305).
        reap_tree(pid) if pid
        finish_capture
      end

      def spawn_shell
        Process.spawn({ CHILD_MARKER => "1" }, ["/bin/sh", "sh"], "-c", @command, chdir: @copy_root,
                                                                                  pgroup: true,
                                                                                  out: @capture_writer,
                                                                                  err: @capture_writer)
      end

      def await_exit(pid, timeout)
        deadline = monotonic + timeout
        loop do
          done, status = Process.wait2(pid, Process::WNOHANG)
          return status.exitstatus || :signal if done
          return :timeout if monotonic >= deadline

          sleep 0.01
        end
      end

      def reap_tree(pid)
        return unless tree_alive?(pid)

        Process.kill("TERM", -pid)
        deadline = monotonic + 2
        sleep 0.02 while monotonic < deadline && tree_alive?(pid)
        Process.kill("KILL", -pid) if tree_alive?(pid)
        Process.wait2(pid)
      rescue SystemCallError
        nil
      end

      def tree_alive?(pid)
        Process.kill(0, -pid)
        true
      rescue SystemCallError
        false
      end

      # A ring buffer on a pipe: output is bounded as it is written, never
      # spooled to disk (Principal, #305). The buffer lives outside the
      # thread so a bounded drain still keeps what was captured.
      def start_capture
        @capture_reader, @capture_writer = IO.pipe
        @capture_buffer = +""
        @capture_thread = Thread.new do
          loop do
            @capture_buffer << @capture_reader.readpartial(16_384)
            if @capture_buffer.bytesize > OUTPUT_LIMIT
              @capture_buffer = @capture_buffer.byteslice(-OUTPUT_LIMIT, OUTPUT_LIMIT)
            end
          end
        rescue IOError # EOFError included: the command closed its output
          nil
        end
      end

      # The command is done, but a descendant that escaped the process
      # group (setsid/daemon) can hold the write end open forever, so the
      # drain is bounded: the reader gets a short grace to see EOF, then it
      # is killed and its captured bytes kept. Escaped sessions are not
      # contained - they only cannot block the run or leak the fd (#305
      # Architect). Both parent ends are always closed.
      def finish_capture
        @capture_writer&.close
        if @capture_thread
          @capture_thread.join(DRAIN_GRACE) || @capture_thread.kill
          @capture_thread.join
        end
        @capture_reader&.close
        @captured = @capture_buffer
        @capture_reader = @capture_writer = @capture_thread = @capture_buffer = nil
      end

      # Captured bytes become report JSON: force UTF-8 and drop invalid
      # sequences - the ring buffer can start mid-multibyte after a
      # truncation (#305 Principal).
      def last_output
        bounded(@captured.to_s).strip.then { |text| text.empty? ? "(no output)" : text }
      end

      def bounded(text)
        text.dup.force_encoding(Encoding::UTF_8).scrub("")[0, OUTPUT_LIMIT]
      end

      def describe_exit(result)
        if SETUP_EXIT_CODES.include?(result)
          "exit #{result} - the shell could not run the command"
        elsif result == :signal
          "killed by a signal"
        elsif result == :timeout
          "timed out"
        elsif result.is_a?(Exception)
          "could not start: #{result.message}"
        else
          "exit #{result}"
        end
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
