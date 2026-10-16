# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "find"
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

      def initialize(command:, root:)
        @command = command
        @root = File.expand_path(root)
        @copy_root = nil
        at_exit { close }
      end

      # Runs the command once on an untouched copy before any mutant
      # exists. A failing command can never claim kills, so fail the whole
      # run here with the command's own output (#140, #305).
      def preflight!(timeout: 60)
        result = with_fresh_copy { spawn_and_wait(timeout) }
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
        status = with_fresh_copy do
          write_subject(subject, mutation)
          verdict_for(spawn_and_wait(timeout))
        end
        Runner::Outcome.new(status: status, runtime: monotonic - started,
                            failed_ids: status == :killed ? [PSEUDO_TEST] : [],
                            executed_ids: status == :error ? [] : [PSEUDO_TEST],
                            message: status == :error ? error_context : nil)
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
        dereference_symlinks
        yield
      end

      # cp_r keeps symlinks, and a write through a link that escapes the
      # copy would land in the real tree. Links resolving inside the tree
      # become real content; anything else refuses the run (#305 QA).
      def dereference_symlinks
        Find.find(@copy_root) do |path|
          next unless File.symlink?(path)

          target = File.realpath(path)
          if target.start_with?("#{@copy_root}/")
            File.unlink(path)
            FileUtils.cp_r(target, path, preserve: true)
          else
            raise Error, "the tree links outside itself: #{path.sub("#{@copy_root}/", '')} -> #{target}; " \
                         "external test commands need a self-contained tree"
          end
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

      def relative(subject)
        subject.file.start_with?("#{@root}/") ? subject.file[(@root.size + 1)..] : subject.file
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
      # spooled to disk (Principal, #305).
      def start_capture
        reader, @capture_writer = IO.pipe
        captured = +""
        @capture_thread = Thread.new do
          begin
            loop do
              captured << reader.readpartial(16_384)
              captured = captured.byteslice(-OUTPUT_LIMIT, OUTPUT_LIMIT) if captured.bytesize > OUTPUT_LIMIT
            end
          rescue IOError # EOFError included: the command closed its output
            nil
          end
          captured
        end
      end

      def finish_capture
        return unless @capture_writer

        @capture_writer.close
        @captured = @capture_thread.value
        @capture_writer = @capture_thread = nil
      end

      def last_output
        @captured.to_s.strip.then { |text| text.empty? ? "(no output)" : text }
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
