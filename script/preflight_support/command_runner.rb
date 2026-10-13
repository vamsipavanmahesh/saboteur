# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "digest"
require "fileutils"

module Preflight
  CommandResult = Struct.new(:argv, :directory, :exit_status, :signal, :timed_out, :spawn_error, :truncated,
                             :invalid_encoding, :stray_processes, :duration_seconds, :stdout, :stderr,
                             :stdout_path, :stderr_path, keyword_init: true) do
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
        stdout_path: stdout_path, stdout_sha256: Digest::SHA256.hexdigest(stdout.to_s),
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
    attr_writer :log_directory

    def initialize(directory:, log_directory: nil, env: {}, grace: GRACE_SECONDS, output_limit: OUTPUT_LIMIT_BYTES,
                   drain: DRAIN_SECONDS)
      @directory = directory
      @log_directory = log_directory
      @env = env
      @settings = { grace: grace, output_limit: output_limit, drain: drain }
      @sequence = 0
      @history = []
    end

    def run(argv, timeout: DEFAULT_TIMEOUT_SECONDS)
      raise ArgumentError, "argv must be an array of strings" unless argv.is_a?(Array) && argv.all?(String)

      started = monotonic
      result = execute(argv, timeout)
      result.duration_seconds = (monotonic - started).round(3)
      write_logs(result)
      @history << result.to_h
      result
    end

    private

    def execute(argv, timeout)
      Open3.popen3(@env, *argv, chdir: @directory, pgroup: true) do |input, out, err, waiter|
        input.close
        buffers = [Capture.new, Capture.new]
        readers = [out, err].zip(buffers).map { |stream, buffer| Thread.new { read_limited(stream, buffer) } }
        timed_out = waiter.join(timeout).nil?
        status = finish(waiter, timed_out)
        stray = group_cleaned_up?(waiter.pid)
        outputs = collect(readers, [out, err], buffers)
        build(argv, { status: status, timed_out: timed_out, stray_processes: stray }, outputs)
      end
    rescue SystemCallError => e
      build(argv, { spawn_error: e.message }, [["", false], ["", false]])
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
      (stdout, out_cut), (stderr, err_cut) = outputs
      status = outcome[:status]
      stdout = text(stdout)
      stderr = text(stderr)
      CommandResult.new(argv: argv, directory: @directory, exit_status: status&.exitstatus || -1,
                        signal: status&.termsig, timed_out: outcome[:timed_out] || false,
                        spawn_error: outcome[:spawn_error] || (status ? nil : "no exit status"),
                        stray_processes: outcome[:stray_processes] || false, truncated: out_cut || err_cut,
                        invalid_encoding: !(stdout.valid_encoding? && stderr.valid_encoding?),
                        stdout: stdout, stderr: stderr)
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

      FileUtils.mkdir_p(@log_directory)
      @sequence += 1
      stem = File.join(@log_directory, format("%03d", @sequence))
      result.stdout_path = "#{stem}.stdout.log"
      result.stderr_path = "#{stem}.stderr.log"
      File.binwrite(result.stdout_path, result.stdout)
      File.binwrite(result.stderr_path, result.stderr)
    rescue SystemCallError => e
      result.spawn_error = "log write failed: #{e.message}"
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
