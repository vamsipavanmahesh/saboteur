# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "workflow"

module Saboteur
  module Baseline
    module Command
      def baseline_parser
        OptionParser.new do |opts|
          opts.banner = "Usage: saboteur baseline check|propose|accept --baseline PATH [--proposal PATH] " \
                        "[--epsilon POINTS]"
          opts.on("--baseline PATH", "Accepted baseline destination") { |value| @baseline_path = value }
          opts.on("--proposal PATH", "Editable proposal path (propose/accept)") { |value| @proposal_path = value }
          opts.on("--previous SHA256", "Reviewed current destination hash for replacement") do |value|
            @previous = value
          end
          opts.on("--epsilon POINTS", Float, "check: also fail when the score drops more than POINTS " \
                                             "percentage points below the baseline's") { |value| @epsilon = value }
          opts.on("--config PATH", "Config file (default config/saboteur.rb)") { |value| set(:config, value) }
          opts.on("--subject EXPR", "Whole subject filter; repeatable") { |value| add_subject(value) }
          opts.on("--seed N", Integer, "Repeatable run seed") { |value| set(:seed, value) }
          opts.on("--format FORMAT", "propose: terminal (default) or json") { |value| @format = value }
          define_color_options(opts)
        end
      end

      private

      def baseline
        return show_help("baseline") if help_requested?

        action = @argv.shift
        parse_baseline(action)
        payload = stdout_on_stderr do
          workflow = Baseline::Workflow.new(config: config, err: @err)
          baseline_action(workflow, action)
        end
        action == "propose" && @format != "json" ? print_proposal(payload) : @out.puts(JSON.generate(payload))
        payload.fetch("exit_code", CLI::EXIT_OK)
      rescue ConfigError, SystemCallError => e
        @err.puts("saboteur: #{e.message}")
        CLI::EXIT_USAGE
      rescue Error => e
        @err.puts("saboteur: #{e.message}")
        CLI::EXIT_TOOL
      end

      def baseline_path_required(action)
        "--baseline PATH is required (for example: saboteur baseline #{action} --baseline baseline.json)"
      end

      def parse_baseline(action)
        raise CLI::UsageError, "baseline expects check, propose or accept" unless %w[check propose
                                                                                     accept].include?(action)

        baseline_parser.parse!(@argv)
        raise CLI::UsageError, "unexpected arguments: #{@argv.join(' ')}" if @argv.any?
        raise CLI::UsageError, baseline_path_required(action) unless @baseline_path
        raise CLI::UsageError, "--proposal PATH is required" if action != "check" && !@proposal_path
        if action == "check" && (@proposal_path || @previous)
          raise CLI::UsageError,
                "check does not use --proposal or --previous"
        end
        validate_epsilon(action)
        raise CLI::UsageError, "--previous needs a SHA-256" if @previous && !@previous.match?(/\A[0-9a-f]{64}\z/)

        validate_format(action)
      end

      def validate_format(action)
        unless @format.nil? || %w[terminal json].include?(@format)
          raise CLI::UsageError, "--format must be terminal or json"
        end
        raise CLI::UsageError, "--format applies to propose only" if @format && action != "propose"
      end

      def validate_epsilon(action)
        return unless @epsilon

        raise CLI::UsageError, "--epsilon applies to check only" if action != "check"
        raise CLI::UsageError, "--epsilon must be between 0 and 100" unless (0.0..100.0).cover?(@epsilon)
      end

      def print_proposal(payload)
        @out.puts("baseline proposal written: #{payload.fetch('proposal')}")
        survivors = payload.fetch("survivors")
        @out.puts("  matched mutants: #{payload.fetch('candidates')} " \
                  "(#{plural(survivors, 'survivor')} to reason about)")
        uncovered, gaps = payload.fetch("gaps", []).partition { |gap| gap.start_with?("no_coverage:") }
        unless uncovered.empty?
          @out.puts("  proposed with #{plural(uncovered.size, 'mutant')} on lines no test runs - " \
                    "the baseline cannot speak for them")
        end
        unless gaps.empty?
          names = gaps.map { |gap| gap.sub(/\A(subject_skipped|omitted):/, "") }
          @out.puts("  proposed with #{plural(names.size, 'untested subject')}: #{names.join(', ')} - " \
                    "the baseline cannot speak for them")
        end
        @out.puts("  next step: give each accepted survivor a reason in the proposal, then run: " \
                  "saboteur baseline accept#{scope_flags} " \
                  "--baseline #{payload.fetch('destination')} --proposal #{payload.fetch('proposal')}")
      end

      def plural(count, noun)
        count == 1 ? "#{count} #{noun}" : "#{count} #{noun}s"
      end

      # accept re-verifies the recorded run settings, so the printed command
      # repeats the scope flags this propose ran with.
      def scope_flags
        flags = +""
        Array(options[:subjects]).each { |expr| flags << " --subject #{expr}" }
        flags << " --seed #{options[:seed]}" if options[:seed]
        flags << " --config #{options[:config]}" if options[:config]
        flags
      end

      def baseline_action(workflow, action)
        case action
        when "check" then workflow.check(path: @baseline_path, epsilon: @epsilon)
        when "propose" then workflow.propose(proposal: @proposal_path, destination: @baseline_path,
                                             previous: @previous)
        when "accept" then workflow.accept(proposal: @proposal_path, destination: @baseline_path, previous: @previous)
        end
      end
    end
  end
end
