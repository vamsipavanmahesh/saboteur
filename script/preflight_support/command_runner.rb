# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "digest"
require "fileutils"

module Preflight
  CommandResult = Struct.new(:argv, :directory, :exit_status, :signal, :timed_out, :spawn_error, :truncated,
                             :invalid_encoding, :stray_processes, :duration_seconds, :stdout, :stderr,
                             :stdout_path, :stderr_path, :data, :data_path, keyword_init: true) do
    def succeeded?
      ran? && exit_status.zero?
    end

    # True only when the process finished by itself, was not killed by a signal, left no process
    # behind, produced all of its output, and that output is valid UTF-8. Anything else is unusable.
    def ran?
      spawn_error.nil? && !timed_out && !truncated && !invalid_encoding && !stray_processes && signal.nil?
    end

    def problem
      return "could not start or finish cleanly: #{spawn_error}" if spawn_error
      return "timed out" if timed_out
      return "killed by signal #{signal}" if signal
      return "output over the byte limit" if truncated
      return "output is not valid UTF-8" if invalid_encoding

      "left processes running after it exited" if stray_processes
    end

    def to_h
      { argv: argv, directory: directory, exit_status: exit_status, signal: signal, timed_out: timed_out,
        truncated: truncated, invalid_encoding: invalid_encoding, stray_processes: stray_processes,
        spawn_error: spawn_error, duration_seconds: duration_seconds,
        stdout_path: stdout_path, data_path: data_path, stdout_sha256: Digest::SHA256.hexdigest(stdout.to_s),
        stderr_path: stderr_path, stderr_sha256: Digest::SHA256.hexdigest(stderr.to_s) }
    end
  end

  # Bytes read so far from one pipe, shared with the reader thread.
  class Capture
    attr_reader :bytes

    def initialize
      @bytes = String.new(encoding: Encoding::BINARY)
    end
  end

  # Runs one command given as an argument array. Never uses a shell.
  # A process group is not a sandbox: a child can detach and candidate code can use the network.
  # Every wait is bounded. The whole process group is cleaned up after every run: TERM, a grace
  # period, then KILL. A run that left processes behind is reported as such and never counts as clean.
  class CommandRunner
    DEFAULT_TIMEOUT_SECONDS = 1800
    GRACE_SECONDS = 5
    DRAIN_SECONDS = 2
    OUTPUT_LIMIT_BYTES = 20 * 1024 * 1024

    attr_reader :history
    attr_writer :log_directory, :log_root

    def initialize(directory:, log_directory: nil, env: {}, isolate_env: false, grace: GRACE_SECONDS,
                   output_limit: OUTPUT_LIMIT_BYTES, drain: DRAIN_SECONDS)
      @directory = directory
      @log_directory = log_directory
      @env = env
      @isolate_env = isolate_env
      @settings = { grace: grace, output_limit: output_limit, drain: drain }
      @sequence = 0
      @history = []
    end

    # The shim a data_pipe child loads through `rspec --require`: it points RSpec's report stream at
    # file descriptor 3 (the pipe below) while stdout stays the suite's own channel, so output a spec
    # prints cannot corrupt the report. No path names the pipe: macOS refuses to open one via /dev/fd.
    DATA_SHIM = <<~RUBY
      # SPDX-License-Identifier: MIT
      # frozen_string_literal: true
      RSpec.configure { |config| config.output_stream = IO.new(3, "w") }
    RUBY

    # Path of the shim, written next to the command logs behind the same swap protection. Needs the
    # log directory: with nowhere harness-owned to write, there is no safe shim to load.
    def data_shim_path
      raise ExecutionGap, "a data pipe needs a log directory for the formatter shim" unless @log_directory

      @data_shim_path ||= begin
        root = @log_root || @log_directory
        SafeOutput.make_directories(@log_directory, root)
        path = File.join(@log_directory, "rspec_fd3_shim.rb")
        SafeOutput.write_new(path, DATA_SHIM, root)
        path
      end
    end

    # With data_pipe the child gets an extra pipe as file descriptor 3. It is read by the
    # harness only: there is no path in the checkout that candidate code could swap for a link.
    def run(argv, timeout: DEFAULT_TIMEOUT_SECONDS, data_pipe: false)
      raise ArgumentError, "argv must be an array of strings" unless argv.is_a?(Array) && argv.all?(String)

      started = monotonic
      result = execute(argv, timeout, data_pipe)
      result.duration_seconds = (monotonic - started).round(3)
      write_logs(result)
      @history << result.to_h
      result
    end

    private

    def execute(argv, timeout, data_pipe)
      data_reader, data_writer = IO.pipe if data_pipe
      options = { chdir: @directory, pgroup: true, unsetenv_others: @isolate_env }
      options[3] = data_writer if data_writer
      Open3.popen3(@env, *argv, **options) do |input, out, err, waiter|
        input.close
        data_writer&.close
        supervise(argv, timeout, waiter, [out, err, data_reader].compact)
      end
    rescue SystemCallError => e
      build(argv, { spawn_error: e.message }, [["", false], ["", false]])
    ensure
      [data_reader, data_writer].each { |io| io.close if io && !io.closed? }
    end

    def supervise(argv, timeout, waiter, streams)
      buffers = streams.map { Capture.new }
      readers = streams.zip(buffers).map { |stream, buffer| Thread.new { read_limited(stream, buffer) } }
      timed_out = waiter.join(timeout).nil?
      status = finish(waiter, timed_out)
      stray = group_cleaned_up?(waiter.pid)
      outputs = collect(readers, streams, buffers)
      build(argv, { status: status, timed_out: timed_out, stray_processes: stray }, outputs)
    end

    # Stops the leader if it overran, then waits a bounded time for its exit status.
    def finish(waiter, timed_out)
      signal_group("TERM", waiter.pid) if timed_out
      return waiter.value unless timed_out

      waiter.join(@settings[:grace]) || signal_group("KILL", waiter.pid)
      waiter.join(@settings[:grace]) ? waiter.value : nil
    end

    # The leader may have exited while descendants live on. Terminate them, then kill.
    def group_cleaned_up?(pid)
      return false unless group_alive?(pid)

      signal_group("TERM", pid)
      deadline = monotonic + @settings[:grace]
      sleep(0.05) while group_alive?(pid) && monotonic < deadline
      signal_group("KILL", pid) if group_alive?(pid)
      true
    end

    def group_alive?(pid)
      Process.kill(0, -pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    # Waits a bounded time for the pipes to drain. A pipe still held open after that is a leak; the bytes
    # captured so far are kept so a caller can still read them.
    def collect(readers, streams, buffers)
      deadline = monotonic + @settings[:drain]
      readers.each_with_index.map do |reader, index|
        next reader.value if reader.join([deadline - monotonic, 0].max)

        reader.kill
        streams[index].close unless streams[index].closed?
        [buffers[index].bytes, true]
      end
    end

    def read_limited(stream, capture)
      cut = false
      loop do
        chunk = stream.readpartial(65_536)
        cut ||= capture.bytes.bytesize + chunk.bytesize > @settings[:output_limit]
        capture.bytes << chunk unless cut
      end
    rescue EOFError
      [capture.bytes, cut]
    rescue IOError
      [capture.bytes, true]
    end

    def build(argv, outcome, outputs)
      (stdout, out_cut), (stderr, err_cut), (data, data_cut) = outputs
      status = outcome[:status]
      stdout = text(stdout)
      stderr = text(stderr)
      data &&= text(data)
      CommandResult.new(argv: argv, directory: @directory, exit_status: status&.exitstatus || -1,
                        signal: status&.termsig, timed_out: outcome[:timed_out] || false,
                        spawn_error: outcome[:spawn_error] || (status ? nil : "no exit status"),
                        stray_processes: outcome[:stray_processes] || false,
                        truncated: [out_cut, err_cut, data_cut].any?,
                        invalid_encoding: ![stdout, stderr, data].compact.all?(&:valid_encoding?),
                        stdout: stdout, stderr: stderr, data: data)
    end

    def text(bytes)
      bytes.dup.force_encoding(Encoding::UTF_8)
    end

    def signal_group(name, pid)
      Process.kill(name, -pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def write_logs(result)
      return unless @log_directory

      root = @log_root || @log_directory
      SafeOutput.make_directories(@log_directory, root)
      @sequence += 1
      stem = File.join(@log_directory, format("%03d", @sequence))
      result.stdout_path = "#{stem}.stdout.log"
      result.stderr_path = "#{stem}.stderr.log"
      SafeOutput.write_new(result.stdout_path, result.stdout, root)
      SafeOutput.write_new(result.stderr_path, result.stderr, root)
      return unless result.data

      result.data_path = "#{stem}.data.log"
      SafeOutput.write_new(result.data_path, result.data, root)
    rescue SystemCallError, ExecutionGap => e
      result.spawn_error = "log write failed: #{e.message}"
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
