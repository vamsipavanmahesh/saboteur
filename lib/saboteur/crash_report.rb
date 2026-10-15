# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "pathname"

module Saboteur
  # Last-resort crash reporting, shared by the CLI's StandardError rescue
  # and the exe-level wrapper: one bounded line on stderr, the full
  # backtrace in a log file the line names, the backtrace on stderr with
  # --verbose, and the same failure as agent JSON when an agent listens.
  # Always returns EXIT_TOOL.
  module CrashReport
    ISSUES_URL = "https://github.com/vamsipavanmahesh/saboteur/issues"

    # Same value as CLI::EXIT_TOOL, kept local so the reporter still works
    # when the CLI itself never finished loading.
    EXIT_TOOL = 3

    # The crash log's file name under the run's cache dir; the runner reads
    # it back to explain a nested run's crash in the failure detail (#296).
    LOG_NAME = "internal-error.log"

    module_function

    def call(error, verbose:, agent:, err:, out:, log_path: nil)
      summary = "internal error (#{error.class}: #{one_line(error.message)})"
      line = "saboteur: #{summary} - please report it: #{ISSUES_URL}"
      written = write_log(log_path, error)
      line = "#{line}; full backtrace: #{display_path(written)}" if written
      err.puts(line)
      err.puts(full_text(error)) if verbose
      out.print(agent_json(summary)) if agent
      EXIT_TOOL
    end

    # A crash message can span lines or carry bytes that are invalid in
    # UTF-8 (a LANG=C failure, say); the one-line diagnostic must survive
    # both, and stay one bounded line.
    def one_line(message)
      text = scrub(message).gsub(/\s+/, " ").strip
      text.length > 160 ? "#{text[0...160]}..." : text
    end

    # Class, full message and backtrace, scrubbed so locale-invalid bytes
    # cannot corrupt the log or the terminal.
    def full_text(error)
      (["#{error.class}: #{scrub(error.message)}"] + Array(error.backtrace).map { |frame| scrub(frame) }).join("\n")
    end

    # Writes the log next to the other run state; returns the written path,
    # or nil when the log cannot be written - the crash itself must still
    # be reported, so an unwritable directory is not a second failure.
    # Reporter::Agent.failure's payload, reproduced minimally for crashes
    # before the CLI's reporter files load: same schema and pretty rendering;
    # the summary is already normalized, so no message cap is needed here.
    def agent_json(summary)
      payload =
        if defined?(Reporter::Agent)
          Reporter::Agent.failure(summary, EXIT_TOOL)
        else
          { version: 1, status: "error", verdict: "tool_failure", exitCode: EXIT_TOOL,
            message: summary, next: { help: "saboteur help run" } }
        end
      "#{JSON.pretty_generate(payload)}\n"
    end

    def write_log(log_path, error)
      return nil unless log_path

      begin
        FileUtils.mkdir_p(File.dirname(log_path))
        # Private like the temp fallback: the runner only reads logs with
        # no group/other bits, from the same no-follow fd (#296).
        File.open(log_path, File::CREAT | File::WRONLY | File::TRUNC, 0o600) do |file|
          file.chmod(0o600)
          file.write("#{full_text(error)}\n")
        end
        return log_path
      rescue SystemCallError, IOError
        # Fall through to the temp fallback.
      end
      write_tmp_log(error)
    end

    # The fallback is computed lazily, only once the primary write failed:
    # an eager tmp_log_path call could itself raise (Dir.tmpdir finds no
    # usable dir) and mask the crash it was meant to log (#296).
    #
    # The fallback path is predictable and lives in a shared directory, so
    # it is created privately: CREAT|EXCL|WRONLY|NOFOLLOW never follows or
    # overwrites a pre-existing file or symlink, and the mode pins the log
    # to 0600. A taken or hostile path means no log - the crash report
    # itself must still go out, so every failure here degrades to nil.
    def write_tmp_log(error)
      File.open(tmp_log_path, File::CREAT | File::EXCL | File::WRONLY | nofollow_flag, 0o600) do |file|
        file.write("#{full_text(error)}\n")
      end
      tmp_log_path
    rescue SystemCallError, IOError, ArgumentError
      nil
    end

    # O_NOFOLLOW where the platform has it (every CI target does).
    def nofollow_flag
      File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0
    end

    # Where the log lands when a configured cache dir is not writable - a
    # sandboxed child holds the project read-only, but the system temp dir is
    # granted (#296). Only a configured log path falls back: cache_dir = nil
    # still means no log at all. Keyed by pid so parallel children never
    # share a file; the runner reads the same path back in the same process.
    def tmp_log_path(pid: Process.pid)
      File.join(Dir.tmpdir, "saboteur-#{pid}-#{LOG_NAME}")
    end

    # The message names the log; relative to the working directory when it
    # sits inside it, so the line stays short.
    def display_path(path)
      relative = Pathname(path).relative_path_from(Pathname(Dir.pwd)).to_s
      relative.start_with?("..") ? path : relative
    rescue ArgumentError
      path
    end

    def scrub(string)
      string.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?")
    end
  end
end
