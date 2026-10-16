# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Execution
    # Runs mutants through a user-supplied shell command (#140): the mutant
    # is written to the real file, the command runs in the project root,
    # and its exit status decides the verdict - 0 survived, non-zero
    # killed, deadline timeout. Explicitly slower than in-process runs: the
    # whole command runs per mutant, with no coverage and no test
    # selection. It is the mode for target apps that cannot load inside
    # this Ruby (apps on older Rubies). The original file bytes come back
    # in an ensure, with an at_exit backstop so a hard kill cannot leave
    # the tree mutated.
    class ExternalRunner
      # The command is one test in the report's eyes: a kill names it as
      # the killer, a run lists it as executed.
      PSEUDO_TEST = "(test command)"

      def initialize(command:, root:)
        @command = command
        @root = root
        @pending = nil
        at_exit { restore_pending }
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

      def run_mutant(subject, mutation, timeout)
        path = File.expand_path(subject.file, @root)
        original = File.binread(path)
        with_restoration(path, original) do
          File.binwrite(path, mutated_source(subject, mutation))
          verdict_for(spawn_and_wait(timeout))
        end
      end

      def verdict_for(result)
        case result
        when :timeout then :timeout
        when Exception then :error
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
        pid = Process.spawn(["/bin/sh", "sh"], "-c", @command, chdir: @root, pgroup: true,
                                                               out: File::NULL, err: File::NULL)
        deadline = monotonic + timeout
        loop do
          done, status = Process.wait2(pid, Process::WNOHANG)
          return status.exitstatus if done

          if monotonic >= deadline
            terminate_tree(pid)
            Process.wait2(pid)
            return :timeout
          end
          sleep 0.01
        end
      rescue SystemCallError => e
        e
      end

      def terminate_tree(pid)
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

      def with_restoration(path, original)
        @pending = [path, original]
        yield
      ensure
        restore_pending
      end

      def restore_pending
        return unless @pending

        path, original = @pending
        @pending = nil
        File.binwrite(path, original)
      rescue SystemCallError
        nil
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
