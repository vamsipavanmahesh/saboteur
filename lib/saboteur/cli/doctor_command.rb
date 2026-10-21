# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # `saboteur doctor`: environment report and optional unchanged suite
    # passes, never mutations (#334). Extracted from CLI by command.
    module DoctorCommand
      def doctor_parser
        OptionParser.new do |opts|
          opts.banner = "Usage: saboteur doctor [--config PATH] [--seed N] [--suite] [--test PATH] [-v] " \
                        "[--color [MODE]]"
          opts.on("--config PATH", "Config file (default config/saboteur.rb)") { |value| set(:config, value) }
          opts.on("--seed N", Integer, "Seed for the two baseline runs (default 1)") { |value| set(:seed, value) }
          opts.on("--suite", "Also run the unchanged suite twice (slow on a large suite)") { set(:suite, true) }
          opts.on("--test PATH", "Spec file or directory for the suite runs; repeatable. Implies --suite") do |value|
            (options[:tests] ||= []) << value
          end
          opts.on("-v", "--verbose", "Full environment detail instead of the summary") { set(:verbose, true) }
          opts.on("--color [MODE]", %w[always never auto],
                  "Colour the summary: always, never or auto (default: auto)") do |value|
            @color = (value || :always).to_sym
          end
        end
      end

      private

      def doctor_command = help_requested? ? show_help("doctor") : doctor

      def doctor
        doctor_parser.parse!(@argv)
        raise UsageError, "unexpected arguments: #{@argv.join(' ')}" if @argv.any?

        options[:tests]&.each { |test| require_existing_test(test) }
        healthy = Doctor.new(config, out: @out,
                                     suite: options[:suite] || options.key?(:tests),
                                     verbose: options.fetch(:verbose, false),
                                     palette: Reporter::Palette.for(@out, mode: @color || :auto)).call
        # 1: at least one summary check failed (the summary prints the Fix lines).
        healthy ? EXIT_OK : 1
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
