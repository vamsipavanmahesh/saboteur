# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../reporter/palette"

module Saboteur
  class CLI
    # Where a failed command speaks: stderr for people, and in agent mode the
    # same failure as JSON on stdout (#334). Extracted from CLI.
    module FailureOutput
      private

      # Last resort: a bug must not escape as a bare stack trace and an accidental exit 1.
      def internal_error(error)
        CrashReport.call(error, verbose: @verbose, agent: agent?, err: @err, out: @out,
                                log_path: crash_log_path, color: @color || :auto)
      end

      # The crash log lives with the other run state. A broken config (or a
      # nil cache_dir) must not swallow the crash report itself: no log.
      def crash_log_path
        config.path("cache_dir")&.then { |dir| File.join(dir, CrashReport::LOG_NAME) }
      rescue StandardError
        nil
      end

      def usage_error(message = nil)
        @err.puts(Reporter::Palette.for(@err, mode: @color || :auto).paint(:fail, message)) if message
        @err.puts(USAGE)
        agent_failure(message || USAGE, EXIT_USAGE)
      end

      def agent? = @format == "agent"

      # In agent mode the failure is also on stdout, where the agent reads its answer.
      def agent_failure(message, exit_code)
        @out.print(Reporter::Agent.render(Reporter::Agent.failure(message, exit_code))) if agent?
        exit_code
      end

      # Error messages interpolate repository-controlled names, so each line is
      # made safe before it is printed (a newline then "::error::" in a file
      # name must not become a workflow command in the CI log).
      def report_failure(error, exit_code)
        message = Text.display_safe_lines(error.message)
        @err.puts(Reporter::Palette.for(@err, mode: @color || :auto).paint(:fail, "saboteur: #{message}"))
        @err.puts(verdict_line(EXIT_BASELINE_RED)) if exit_code == EXIT_BASELINE_RED
        agent_failure(message, exit_code)
      end

      # The terminal verdict names the reason for a nonzero exit. Painted
      # red under the same colour rules as the report.
      def verdict_line(code)
        Reporter::Palette.for(@err, mode: @color || :auto).paint(:fail, ErrorCause.verdict_line(code))
      end
    end
  end
end
