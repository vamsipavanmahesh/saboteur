# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "optparse"
require_relative "../saboteur"
require_relative "crash_report"
require_relative "doctor"
require_relative "help"
require_relative "reporter/replay"
require_relative "baseline/command"
require_relative "cli/exit_status"
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

module Saboteur
  class CLI
    include Baseline::Command
    include ExitStatus
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

    USAGE = "Usage: saboteur run [SOURCE...] [--test TEST...] [--all] [--threshold PERCENT] [--since REF] " \
            "[--subject 'Klass#meth'] [--timeout-factor N] [--jobs N] [--seed N] [--id DIGEST]
" \
            "Run 'saboteur help' for every command, option, config key and exit code."

    EXIT_OK = 0
    EXIT_SURVIVORS = 1
    EXIT_USAGE = 2
    EXIT_TOOL = 3
    EXIT_BUDGET = 4
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

    def run_command = help_requested? ? show_help("run") : run

    def history_entry(command) = help_requested? ? show_help(command) : history_command(command)

    def help_requested? = @argv.intersect?(%w[--help -h])

    def show_help(command_name)
      help = Help.new(option_lines: option_lines)
      text = command_name ? help.command(command_name) : help.overview
      return @out.puts(text) || EXIT_OK if text

      @err.puts("unknown command: #{command_name}. Commands: #{help.command_names.join(', ')}")
      EXIT_USAGE
    end

    def usage_error(message = nil)
      @err.puts(message) if message
      @err.puts(USAGE)
      agent_failure(message || USAGE, EXIT_USAGE)
    end

    def agent? = @format == "agent"

    def agent_requested? = self.class.agent_requested?(@argv)

    # In agent mode the failure is also on stdout, where the agent reads its answer.
    def agent_failure(message, exit_code)
      @out.print(Reporter::Agent.render(Reporter::Agent.failure(message, exit_code))) if agent?
      exit_code
    end

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
      @err.puts("saboteur: #{e.message}")
      agent_failure(e.message, EXIT_USAGE)
    rescue Error => e
      @err.puts("saboteur: #{e.message}")
      agent_failure(e.message, EXIT_TOOL)
    end

    # Mutants run your code, and a mutant of code that writes or deletes files
    # can change the tree. Say so up front when uncommitted work is at stake.
    # The scope the warning names is the configured one: positional source
    # operands narrow the run after the warning, so the include/exclude they
    # imply stay out of its config (#309, #503 review).
    def warn_dirty_tree
      warning = @sources ? Config.load(path: options[:config], overrides: overrides.except(:include, :exclude)) : config
      DirtyTreeWarning.for(warning, config_path: options[:config])&.then { |text| @err.puts(text) }
    end

    # Contradictory selection flags are a usage error before any file or
    # repository check: --test wins over inference by precedence, but only
    # one of them may be named. Config-file combinations are not errors:
    # --test wins there, so generated commands stay valid over any config.
    def reject_test_selection_conflicts
      raise UsageError, "--all cannot be combined with --test" if options[:all] && options[:tests]&.any?

      reject_test_command_conflicts
      raise UsageError, "--all cannot be combined with --guess-tests" if options[:all] && options[:guess_tests]
      return unless options[:guess_tests] && options[:tests]&.any?

      raise UsageError, "--guess-tests cannot be combined with --test"
    end

    # --test-command replaces the whole in-process test machinery: test
    # selection, coverage, parallelism and the sandbox do not apply.
    def reject_test_command_conflicts
      return unless options[:test_command]

      # options[:tests] is nil or a non-empty list, so truthiness is the check.
      raise UsageError, "--test-command cannot be combined with --test" if options[:tests]
      raise UsageError, "--test-command cannot be combined with --incremental" if options[:incremental]
    end

    # Usage errors found before the target boots.
    def validate_run_options
      reject_format_conflicts
      validate_shard_options
      Selection::GitDiff.verify_ref!(config["since"], root: config.root) if config["since"]
    end

    # Agent mode allows no score gates (one strict exit 0); the json inventory is --dry-run planning only.
    def reject_format_conflicts
      if agent? && (config["threshold"] || gates.any?)
        raise UsageError, "#{config['threshold'] ? '--threshold' : gates.agent_option_name} " \
                          "cannot be combined with --agent"
      end
      return unless @format == "json" && !options[:dry_run]

      raise UsageError, "--format json is the --dry-run mutant inventory; a run summary is --format agent"
    end

    # One line naming the reports written, paths relative to the root when
    # they sit under it (a blank line before it, as the old JSON line had).
    def announce_reports(reports)
      return if (written = reports.select { |path, _label| path }).empty?

      root = File.join(File.realpath(config.root), "")
      names = written.map do |path, label|
        shown = File.expand_path(path).delete_prefix(root)
        "#{shown} (#{label})"
      end
      @out.puts "\nReports: #{names.join(', ')}"
    end

    # Agent mode: stdout carries exactly one JSON payload. The target's own output (boot
    # files, hooks, spec loading, child processes) goes to stderr while the engine runs.
    # Descriptor 1 points at stderr for the block, so Kernel#puts, system and forked
    # children cannot write into the JSON on stdout.
    def stdout_on_stderr
      saved = $stdout.dup
      $stdout.reopen($stderr)
      yield
    ensure
      $stdout.reopen(saved) if saved
      saved&.close
    end

    # Positional arguments name the files (or directories) to mutate. They
    # replace the configured include and exclude patterns. Each must exist,
    # so a typo is an error and not a run over zero subjects.
    def use_explicit_sources
      Selection::SourceScope.verify_no_specs!(@argv)
      options[:tests]&.each { |test| require_existing_test(test) }
      # --test may stand alone: the configured include (or the --since
      # diff) names the sources. The files must still exist.
      return if @argv.empty?

      @sources = @argv.dup
      options[:include] = @argv.map { |source| source_pattern(source) }
      options[:exclude] = []
    end

    def source_pattern(source)
      return "#{glob_escape(source.chomp('/'))}/**/*.rb" if File.directory?(source)
      raise UsageError, "source is not a Ruby file: #{source}" if File.file?(source) && !source.end_with?(".rb")
      raise UsageError, "source file not found: #{source}" unless File.file?(source)

      glob_escape(source)
    end

    # include is a list of glob patterns; a named file must match only itself.
    def glob_escape(path)
      path.gsub(/[\\*?\[\]{}]/) { |character| "\\#{character}" }
    end

    # A test may carry an example selector: spec/a_spec.rb:12 or spec/a_spec.rb[1:2].
    def require_existing_test(test)
      path = test.sub(/(:\d+|\[[\d:,]+\])+\z/, "")
      raise UsageError, "test file not found: #{test}" unless File.exist?(path)
    end

    def overrides = options.except(:config, :id, :suite, :list_operators, :dry_run)

    def preview
      raise UsageError, "--dry-run and --list-operators print text, not --agent JSON; use --format json" if agent?
      raise UsageError, "--id replays one mutant: not with --dry-run or --list-operators" if options[:id]

      if options[:list_operators]
        MutationSource::OperatorRegistry.list(@out, names: config["operators"], excluded: config["exclude_operators"])
        return EXIT_OK
      end

      Preview.new(config, out: @out, err: @err, format: @format).call
      EXIT_OK
    end

    def add_subject(expr) = (options[:subjects] ||= []) << expr

    def set(key, value) = (options[key] = value)
  end
end
