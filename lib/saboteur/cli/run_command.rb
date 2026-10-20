# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # `saboteur run`: parse, validate, then preview or execute (#334).
    # Extracted from CLI by command.
    module RunCommand
      private

      def run_command = help_requested? ? show_help("run") : run

      def run
        parser.parse!(@argv)
        reject_test_selection_conflicts
        use_explicit_sources
        validate_run_options
        warn_dirty_tree

        config.deprecation_warnings.each { |warning| @err.puts("saboteur: #{warning}") }

        return preview if options[:list_operators] || options[:dry_run]

        refuse_empty_source_set
        execute_run
      rescue ConfigError => e
        report_failure(e, EXIT_USAGE)
      rescue Error => e
        report_failure(e, EXIT_TOOL)
      end
    end
  end
end
