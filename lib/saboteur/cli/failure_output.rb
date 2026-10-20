# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # Where a failed command speaks: stderr for people, and in agent mode the
    # same failure as JSON on stdout (#334). Extracted from CLI.
    module FailureOutput
      private

      def usage_error(message = nil)
        @err.puts(message) if message
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
        @err.puts("saboteur: #{message}")
        agent_failure(message, exit_code)
      end
    end
  end
end
