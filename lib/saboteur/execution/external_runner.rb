# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"
require "tmpdir"

module Saboteur
  module Execution
    # Runs mutants through a user-supplied shell command (#140): mutants are
    # written into a DISPOSABLE COPY of the project tree, never the real
    # files, and the command runs there with the caller's permissions -
    # unsandboxed, with network and side effects, exactly as if typed into a
    # shell. Its exit status decides the verdict: 0 survived, non-zero
    # killed (except 126/127, which read as command/setup errors), deadline
    # timeout. Explicitly slower than in-process runs: the whole command
    # runs per mutant, with no coverage and no test selection, and the tree
    # copy itself costs one recursive copy per run. It is the mode for
    # target apps that cannot load inside this Ruby (apps on older Rubies).
    #
    # Safety shape: because only the copy is mutated, a SIGKILL of this
    # process, a failed write, or a command that keeps writing in the
    # background can never damage the real tree - the worst case is a
    # leaked temp directory under the system tmp dir. The command's whole
    # process group is TERM/KILLed in an ensure on every exit path
    # (verdict, timeout, error, interrupt), so background descendants
    # cannot outlive a mutant run. A neutral preflight runs the command
    # once on the unchanged copy before any mutant is created, so a typo
    # command fails immediately with its own stderr.
    class ExternalRunner
      # The command is one test in the report's eyes: a kill names it as
      # the killer, a run lists it as executed.
      PSEUDO_TEST = "(test command)"

      # Shell "cannot execute" / "command not found" read as setup errors,
      # never as kills: the suite did not run.
      SETUP_EXIT_CODES = [126, 127].freeze

      # Nested saboteur runs: the child inherits this marker and refuses to
      # start, so a test command that itself invokes saboteur cannot mutate
      # the copy mid-run.
      CHILD_MARKER = "SABOTEUR_EXTERNAL_CHILD"

      # Bounded diagnostic capture: the last bytes of combined output kept
      # for preflight and error messages.
      OUTPUT_LIMIT = 64 * 1024

      def initialize(command:, root:)
        if ENV[CHILD_MARKER]
          raise Error, "saboteur is already running an external test command " \
                       "(#{CHILD_MARKER} is set); refusing to start a nested run"
        end

        @command = command
        @root = File.expand_path(root)
        @copy = nil
        at_exit { cleanup_copy }
      end

      # Runs the command once on the unchanged copy before any mutant
      # exists. A failing command can never claim kills, so fail the whole
      # run here with the command's own output (#140, #305).
      def preflight!(timeout: 60)
        result = spawn_and_wait(timeout)
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
      # to the in-process machinery and are ignored here.
      def run(subject:, text:, test_ids:, timeout:, mutation: nil, eval_prefix: nil) # rubocop:disable Lint/UnusedMethodArgument
        started = monotonic
        status = if mutation
                   run_mutant(subject, mutation, timeout)
                 else
                   verdict_for(spawn_and_wait(timeout))
                 end
        Runner::Outcome.new(status: status, runtime: monotonic - started,
                            failed_ids: status == :killed ? [PSEUDO_TEST] : [],
                            executed_ids: status == :error ? [] : [PSEUDO_TEST])
      end

      private

      # The disposable copy of the tree, made once per runner before any
      # mutation (Principal P1): real copies, not hardlinks, so writing a
      # mutant can never corrupt the original inode.
      def copy_root
        @copy_root ||= begin
          dir = Dir.mktmpdir("saboteur-external-")
          FileUtils.cp_r(File.join(@root, "."), dir, preserve: true)
          dir
        end
      end

      def cleanup_copy
        FileUtils.rm_rf(@copy) if @copy
      rescue SystemCallError
        nil
      end

      def run_mutant(subject, mutation, timeout)
        # subject.file is relative to the root in engine runs; specs pass
        # absolute paths under the root. Both resolve inside the copy.
        relative = subject.file.start_with?("#{@root}/") ? subject.file[(@root.size + 1)..] : subject.file
        path = File.join(copy_root, relative)
        File.binwrite(path, mutated_source(subject, mutation))
        verdict_for(spawn_and_wait(timeout))
      rescue SystemCallError
        # A command that deletes the source or replaces it with a
        # directory must not read as survived: the suite did not run.
        :error
      end

      def verdict_for(result)
        case result
        when :timeout then :timeout
        when Exception, :signal, *SETUP_EXIT_CODES then :error
        when 0 then :survived
        else :killed
        end
      end

      # The mutation's edits apply at absolute byte offsets in the file.
      def mutated_source(subject, mutation)
        source = subject.file_source.dup.b
        mutation.edits.sort_by(&:start_byte).reverse_each do |edit|
          source = source.byteslice(0, edit.start_byte) + edit.replacement.b + source.byteslice(edit.end_byte..)
        end
        source.force_encoding(Encoding::UTF_8)
      end

      def spawn_and_wait(timeout)
        # Always through the shell: users write pipelines and redirects,
        # and a bare unknown word must exit 127 instead of raising ENOENT.
        @output = Tempfile.new("saboteur-external-out")
        pid = spawn_shell
        await_exit(pid, timeout)
      rescue SystemCallError => e
        e
      ensure
        # The whole process group goes down on every exit path - verdict,
        # timeout, error and interrupt alike - so background descendants
        # cannot write after the verdict is in (#305).
        reap_tree(pid) if pid
        capture_output
      end

      def spawn_shell
        Process.spawn({ CHILD_MARKER => "1" }, ["/bin/sh", "sh"], "-c", @command, chdir: copy_root,
                                                                                  pgroup: true,
                                                                                  out: @output, err: @output)
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
        terminate_tree(pid)
        Process.wait2(pid)
      rescue SystemCallError
        nil
      end

      def terminate_tree(pid)
        return unless tree_alive?(pid)

        Process.kill("TERM", -pid)
        deadline = monotonic + 2
        sleep 0.02 while monotonic < deadline && tree_alive?(pid)
        Process.kill("KILL", -pid) if tree_alive?(pid)
      rescue SystemCallError
        nil
      end

      def tree_alive?(pid)
        Process.kill(0, -pid)
        true
      rescue SystemCallError
        false
      end

      def capture_output
        return unless @output

        @output.flush
        size = @output.size
        @output.rewind
        @output.seek(size - OUTPUT_LIMIT) if size > OUTPUT_LIMIT
        @captured = @output.read
        @output.close!
        @output = nil
      end

      def last_output
        @captured.to_s.strip.then { |text| text.empty? ? "(no output)" : text }
      end

      def describe_exit(result)
        if SETUP_EXIT_CODES.include?(result)
          "exit #{result} - the shell could not run the command"
        elsif result == :signal
          "killed by a signal"
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
