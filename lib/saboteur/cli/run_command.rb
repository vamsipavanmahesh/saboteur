# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # `saboteur run`: parse, validate, then preview or execute (#334).
    # Extracted from CLI by command.
    module RunCommand
      # The baseline-red shapes the engine raises as Saboteur::Error when the
      # unchanged suite itself fails: the user's tests are broken, so no
      # mutant was ever judged. These route to EXIT_BASELINE_RED; every other
      # deliberate raise keeps EXIT_TOOL.
      BASELINE_RED_MESSAGE = /\A#{Regexp.union(
        'baseline check ', 'baseline has no tests', 'the unchanged suite failed',
        'the test command fails on the unchanged tree'
      )}/

      private

      # A fresh checkout has no config file: say once that defaults are in
      # use, and who writes one (#1172). Agent output stays machine-clean;
      # there is no init command - the Rails generator writes the config.
      def announce_missing_config_file(palette)
        # @format, not agent_requested?: parse! has already eaten --format.
        return if @format == "agent" || config.config_file_present

        path = options[:config] || Config::FILE
        notice = "saboteur: no #{path} - using defaults (Rails: bundle exec rails generate saboteur:install writes one)"
        @err.puts(palette.paint(:dim, notice))
      end

      def baseline_red?(error)
        error.message.to_s.match?(BASELINE_RED_MESSAGE)
      end

      def run_command = help_requested? ? show_help("run") : run

      def run
        parser.parse!(@argv)
        reject_test_selection_conflicts
        use_explicit_sources
        validate_run_options
        warn_dirty_tree

        notices = Reporter::Palette.for(@err, mode: @color || :auto, overrides: config["palette"])
        config.deprecation_warnings.each do |warning|
          @err.puts(Reporter::Notice.paint(notices, "saboteur: #{warning}"))
        end
        announce_missing_config_file(notices)

        return preview if options[:list_operators] || options[:dry_run]

        refuse_empty_source_set
        execute_run
      rescue ConfigError => e
        report_failure(e, EXIT_USAGE)
      rescue Error => e
        report_failure(e, baseline_red?(e) ? EXIT_BASELINE_RED : EXIT_TOOL)
      end
    end
  end
end
