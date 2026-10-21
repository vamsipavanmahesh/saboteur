# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # `saboteur doctor`: environment report and optional unchanged suite
    # passes, never mutations (#334). Extracted from CLI by command.
    module DoctorCommand
      def doctor_parser
        OptionParser.new do |opts|
          opts.banner = "Usage: saboteur doctor [--config PATH] [--seed N] [--suite] [--test PATH]"
          opts.on("--config PATH", "Config file (default config/saboteur.rb)") { |value| set(:config, value) }
          opts.on("--seed N", Integer, "Seed for the two baseline runs (default 1)") { |value| set(:seed, value) }
          opts.on("--suite", "Also run the unchanged suite twice (slow on a large suite)") { set(:suite, true) }
          opts.on("--test PATH", "Spec file or directory for the suite runs; repeatable. Implies --suite") do |value|
            (options[:tests] ||= []) << value
          end
        end
      end

      private

      def doctor_command = help_requested? ? show_help("doctor") : doctor

      # The environment is healthy only if a run would have something to
      # mutate: the same empty source set `run` refuses (exit 2).
      def doctor_verdict
        return EXIT_OK unless config.included_files.empty?

        @err.puts("saboteur: #{empty_source_set_message}")
        EXIT_USAGE
      end

      def doctor
        doctor_parser.parse!(@argv)
        raise UsageError, "unexpected arguments: #{@argv.join(' ')}" if @argv.any?

        options[:tests]&.each { |test| require_existing_test(test) }
        Doctor.new(config, out: @out, suite: options[:suite] || options.key?(:tests)).call
        doctor_verdict
      rescue ConfigError => e
        @err.puts("saboteur: #{Text.display_safe_lines(e.message)}")
        EXIT_USAGE
      rescue Error => e
        @err.puts("saboteur: #{Text.display_safe_lines(e.message)}")
        EXIT_TOOL
      end
    end
  end
end
