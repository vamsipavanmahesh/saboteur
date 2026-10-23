# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../install"

module Saboteur
  class CLI
    # `saboteur install` (#1317): writes the two GitHub Actions workflows that
    # build the whole-suite map on main and restore it on pull requests. It
    # needs no Rails; the Rails generator writes the starter files as well.
    module InstallCommand
      private

      def install_command
        return show_help("install") if help_requested?
        raise UsageError, "unexpected arguments: #{@argv.join(' ')}" if @argv.any?

        results = Install.new(root: Dir.pwd).ci_workflows
        results.each { |result| @out.puts(install_line(result)) }
        @out.puts(Install::Workflows::NEXT_STEP) if results.any? { |result| result.status == :created }
        EXIT_OK
      rescue UsageError => e
        @err.puts("saboteur: #{e.message}")
        EXIT_USAGE
      end

      def install_line(result)
        note = result.status == :skipped ? " (already there, left as it is)" : ""
        "#{result.status.to_s.rjust(8)}  #{result.path}#{note}"
      end
    end
  end
end
