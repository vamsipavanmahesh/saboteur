# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "optparse"
require_relative "../saboteur"
require_relative "crash_report"
require_relative "doctor"
require_relative "help"
require_relative "reporter/replay"
require_relative "baseline/command"
require_relative "baseline/run_gate"
require_relative "cli/error_cause"
require_relative "cli/exit_status"
require_relative "cli/baseline_gate"
require_relative "preview"
require_relative "cli/run_reporting"
require_relative "cli/survivors_command"
require_relative "cli/source_set"
require_relative "cli/run_budget_options"
require_relative "cli/shard_options"
require_relative "cli/selection_options"
require_relative "cli/presets"
require_relative "cli/help_options"
require_relative "cli/history_command"
require_relative "cli/execution_options"
require_relative "cli/matrix_option"
require_relative "cli/output_options"
require_relative "cli/explicit_file_options"
require_relative "cli/doctor_command"
require_relative "cli/agent_provenance"
require_relative "cli/preview_command"
require_relative "cli/help_command"
require_relative "cli/run_validation"
require_relative "cli/explicit_sources"
require_relative "cli/run_output"
require_relative "cli/dirty_tree_notice"
require_relative "cli/run_command"
require_relative "cli/failure_output"

module Saboteur
  class CLI
    include Baseline::Command
    include ExitStatus
    include BaselineGate
    include RunReporting
    include SurvivorsCommand
    include SourceSet
    include RunBudgetOptions
    include ShardOptions
    include SelectionOptions
    include Presets
    include HistoryCommand
    include ExecutionOptions
    include MatrixOption
    include OutputOptions
    include ExplicitFileOptions
    include DoctorCommand
    include AgentProvenance
    include HelpOptions
    include PreviewCommand
    include HelpCommand
    include RunValidation
    include ExplicitSources
    include RunOutput
    include DirtyTreeNotice
    include RunCommand
    include FailureOutput

    USAGE = "Usage: saboteur run [SOURCE...] [--test TEST...] [--all] [--threshold PERCENT] [--since REF] " \
            "[--subject 'Klass#meth'] [--timeout-factor N] [--jobs N] [--seed N] [--id DIGEST]
" \
            "Run 'saboteur help' for every command, option, config key and exit code."

    EXIT_OK = 0
    EXIT_SURVIVORS = 1
    EXIT_USAGE = 2
    EXIT_TOOL = 3
    EXIT_BUDGET = 4
    EXIT_BASELINE_RED = 5
    EXIT_CRASH = 70
    class UsageError < ConfigError; end

    attr_reader :options

    # Found before parsing, so any error, even a bad option that comes first, still
    # answers an agent with JSON. Class-level: the executable's fallback reads raw arguments.
    def self.agent_requested?(argv)
      argv.include?("--agent") || argv.include?("--format=agent") ||
        argv.each_cons(2).any? { |flag, value| flag == "--format" && value == "agent" }
    end

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv.dup
      @out = out
      @err = err
      @options = {}
      @format = "agent" if agent_requested?
    end

    def call
      command = @argv.shift
      case command
      when "run" then run_command
      when "baseline" then baseline
      when "survivors" then survivors_command
      when "doctor" then doctor_command
      when "badge", "trend" then history_entry(command)
      when "version", "--version" then @out.puts(VERSION) || EXIT_OK
      when "help", "--help", "-h" then show_help(@argv.shift)
      when "agent-skill" then @out.print(AgentSkill::TEXT) || EXIT_OK
      else preset_or_usage_error(command)
      end
    rescue OptionParser::ParseError => e
      usage_error(e.message)
    rescue StandardError => e then internal_error(e)
    end

    def config
      @config ||= Config.load(root: Dir.pwd, path: options[:config], overrides: overrides)
    end

    def parser
      OptionParser.new do |opts|
        opts.banner = USAGE
        define_selection_options(opts)
        define_explicit_file_options(opts)
        define_execution_options(opts)
        define_matrix_option(opts)
        define_output_options(opts)
      end
    end

    private

    def history_entry(command) = help_requested? ? show_help(command) : history_command(command)

    def agent_requested? = self.class.agent_requested?(@argv)

    def overrides = options.except(:config, :id, :suite, :list_operators, :dry_run, :all_mutants, :quiet)

    def add_subject(expr) = (options[:subjects] ||= []) << expr

    def set(key, value) = (options[key] = value)
  end
end
