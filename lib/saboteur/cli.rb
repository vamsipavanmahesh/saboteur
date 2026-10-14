# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "optparse"
require_relative "../saboteur"
require_relative "doctor"
require_relative "help"
require_relative "reporter/replay"
require_relative "baseline/command"
require_relative "cli/exit_status"
require_relative "preview"
require_relative "cli/run_reporting"

module Saboteur
  class CLI
    include Baseline::Command
    include ExitStatus
    include RunReporting

    USAGE = "Usage: saboteur run [SOURCE...] [--test TEST...] [--all] [--threshold PERCENT] [--since REF] " \
            "[--subject 'Klass#meth'] [--timeout-factor N] [--jobs N] [--seed N] [--id DIGEST]
" \
            "Run 'saboteur help' for every command, option, config key and exit code."

    EXIT_OK = 0
    EXIT_SURVIVORS = 1
    EXIT_USAGE = 2
    EXIT_TOOL = 3
    class UsageError < ConfigError; end

    attr_reader :options

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv.dup
      @out = out
      @err = err
      @options = {}
      @format = "agent" if agent_requested?
    end

    def call
      case @argv.shift
      when "run" then run_command
      when "baseline" then baseline
      when "doctor" then help_requested? ? show_help("doctor") : doctor
      when "version", "--version" then @out.puts(VERSION) || EXIT_OK
      when "help" then show_help(@argv.shift)
      when "agent-skill" then @out.print(AgentSkill::TEXT) || EXIT_OK
      when "--help", "-h" then show_help(nil)
      else usage_error
      end
    rescue OptionParser::ParseError => e
      usage_error(e.message)
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

    # Each command's own option lines, as printed under OPTIONS in `saboteur help`.
    def option_lines
      { "run" => parser.summarize, "doctor" => doctor_parser.summarize, "baseline" => baseline_parser.summarize }
    end

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

    def run_command
      help_requested? ? show_help("run") : run
    end

    def help_requested?
      @argv.intersect?(%w[--help -h])
    end

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

    def agent?
      @format == "agent"
    end

    # Found before parsing, so any error, even a bad option that comes first, still
    # answers an agent with JSON.
    def agent_requested?
      @argv.include?("--agent") || @argv.include?("--format=agent") ||
        @argv.each_cons(2).any? { |flag, value| flag == "--format" && value == "agent" }
    end

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
    def warn_dirty_tree
      WorkingTree.new(config.root, ignored: config.output_paths).state.warning&.then { |text| @err.puts(text) }
    end

    # Contradictory selection flags are a usage error before any file or
    # repository check: --test wins over inference by precedence, but only
    # one of them may be named. Config-file combinations are not errors:
    # --test wins there, so generated commands stay valid over any config.
    def reject_test_selection_conflicts
      raise UsageError, "--all cannot be combined with --test" if options[:all] && options[:tests]&.any?
      raise UsageError, "--all cannot be combined with --guess-tests" if options[:all] && options[:guess_tests]
      return unless options[:guess_tests] && options[:tests]&.any?

      raise UsageError, "--guess-tests cannot be combined with --test"
    end

    # Usage errors found before the target boots.
    def validate_run_options
      reject_threshold_with_agent_format
      Selection::GitDiff.verify_ref!(config["since"], root: config.root) if config["since"]
    end

    # Agent mode has one strict meaning for exit 0, so a score threshold cannot also decide it.
    def reject_threshold_with_agent_format
      return unless agent? && (config["threshold"] || gates.any?)

      raise UsageError, "#{config['threshold'] ? '--threshold' : '--max-* gates'} cannot be combined with --agent"
    end

    # One line naming the reports written, paths relative to the root when
    # they sit under it (a blank line before it, as the old JSON line had).
    def announce_reports(reports)
      written = reports.select { |path, _label| path }
      return if written.empty?

      root = File.join(File.realpath(config.root), "")
      names = written.map do |path, label|
        shown = File.expand_path(path).delete_prefix(root)
        "#{shown} (#{label})"
      end
      @out.puts "\nReports: #{names.join(', ')}"
    end

    def doctor
      doctor_parser.parse!(@argv)
      raise UsageError, "unexpected arguments: #{@argv.join(' ')}" if @argv.any?

      options[:tests]&.each { |test| require_existing_test(test) }
      Doctor.new(config, out: @out, suite: options[:suite] || options.key?(:tests)).call
      EXIT_OK
    rescue ConfigError => e
      @err.puts("saboteur: #{e.message}")
      EXIT_USAGE
    rescue Error => e
      @err.puts("saboteur: #{e.message}")
      EXIT_TOOL
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

    def agent_provenance(report, tree, engine)
      Reporter::Agent::Provenance.new(
        ref: config["since"], seed: report.seed, head: tree.head, working_tree: tree.label,
        changed_files: tree.changed_files, mode: agent_mode, json_report: config.path("json_report"),
        subjects: Array(config["subjects"]), tests: Array(engine.guessed_tests || config["tests"]),
        sources: @sources || [],
        config_path: options[:config], digest: options[:id], cache: config["cache"],
        incremental: config["incremental"], settings: agent_settings
      )
    end

    # A whole-suite run records its scope as --all, so the generated rerun
    # and replay commands do not default back to inference (which can exit
    # 2 in a project with a spec-less source file).
    def agent_settings
      settings = options.slice(*Reporter::Agent::Commands::SETTING_FLAGS.keys)
                        .merge(operators: config["operators"], exclude_operators: config["exclude_operators"])
      # The effective mode: named tests win over a configured whole-suite
      # selection by precedence, so all is recorded only when no tests
      # resolved - otherwise the follow-up commands would carry both --all
      # and --test, which the CLI rejects.
      settings[:all] = true if (config["all"] || config["test_selection"] == "all") && config["tests"].empty?
      settings
    end

    def agent_mode
      return "replay" if options[:id]
      return "diff" if config["since"]

      @sources&.any? ? "files" : "full"
    end

    # Writes the JSON report and returns its path, or nil when none is configured.
    def write_json(report, cause)
      path = config.path("json_report")
      return unless path

      Reporter::Stryker.new(path).call(report, exit_cause: cause)
      path
    end

    def write_html(report)
      path = config.path("html_report")
      return unless path

      Reporter::Html.new(path).call(report)
      path
    end

    # Positional arguments name the files (or directories) to mutate. They
    # replace the configured include and exclude patterns. Each must exist,
    # so a typo is an error and not a run over zero subjects.
    def use_explicit_sources
      if @argv.empty?
        # --test may stand alone: the configured include (or the --since
        # diff) names the sources. The files must still exist.
        options[:tests]&.each { |test| require_existing_test(test) }
        return
      end

      @sources = @argv.dup
      options[:include] = @argv.map { |source| source_pattern(source) }
      options[:exclude] = []
      options[:tests]&.each { |test| require_existing_test(test) }
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

    def overrides
      options.except(:config, :id, :suite, :list_operators, :dry_run)
    end

    def preview
      raise UsageError, "--dry-run and --list-operators print text, not --agent JSON" if agent?
      raise UsageError, "--id replays one mutant: not with --dry-run or --list-operators" if options[:id]

      if options[:list_operators]
        MutationSource::OperatorRegistry.list(@out, names: config["operators"], excluded: config["exclude_operators"])
        return EXIT_OK
      end

      Preview.new(config, out: @out, err: @err).call
      EXIT_OK
    end

    def define_selection_options(opts)
      opts.on("--operators NAMES", Array, "Choose operator names (default: all)") do |v|
        set(:operators, v)
      end
      opts.on("--exclude-operators NAMES", Array, "Exclude operator names from the selected set") do |v|
        set(:exclude_operators, v)
      end
      opts.on("--list-operators", "List operator names and descriptions") { set(:list_operators, true) }
      opts.on("--dry-run", "Preview mutants without boot, tests, forks or report writes") { set(:dry_run, true) }
      opts.on("--id DIGEST", "Replay exactly one current mutant by its full digest") { |v| set(:id, v) }
      opts.on("--since REF", "Only mutate subjects changed since git REF") { |v| options[:since] = v }
      opts.on("--subject EXPR", "Klass#meth, Klass.meth or a namespace; repeatable") { |v| add_subject(v) }
    end

    def define_execution_options(opts)
      opts.on("--timeout-factor N", Float, "Multiple of baseline runtime (default 3)") { |v| set(:timeout_factor, v) }
      opts.on("--jobs N", Integer, "Concurrent workers (default 1)") { |v| set(:jobs, v) }
      opts.on("--seed N", Integer, "Seed for Ruby's random numbers in every test run (default 1)") do |v|
        set(:seed, v)
      end
      opts.on("--config PATH", "Config file (default config/saboteur.rb)") { |v| set(:config, v) }
      opts.on("--integration NAME", "Test adapter (rspec)") { |v| set(:integration, v) }
      opts.on("--reeval STRATEGY", Execution::Reevaluator::STRATEGIES, "class_eval or nesting") { |v| set(:reeval, v) }
      opts.on("--no-cache", "Rebuild the coverage map") { set(:cache, false) }
      opts.on("--allow-hazardous", "Also run mutants inside destructive calls (rm_rf, system, ...)") do
        set(:allow_hazardous, true)
      end
      opts.on("--fail-fast", "Stop after the first subject with a survivor (needs --jobs 1)") { set(:fail_fast, true) }
      opts.on("--incremental", "Reuse earlier verdicts whose inputs did not change") { set(:incremental, true) }
      opts.on("--allow-focus", "Run even when a focus filter (fit, fdescribe, :focus) narrows the suite") do
        set(:allow_focus, true)
      end
      opts.on("--all", "Run the whole configured test suite instead of inferring the specs named after the " \
                       "mutated files") { set(:all, true) }
      opts.on("--[no-]guess-tests", "Deprecated alias: inferred specs are already the default; " \
                                    "--no-guess-tests warns and is ignored - use --all for the whole suite") do |v|
        set(:guess_tests, v)
      end
    end

    def define_matrix_option(opts)
      opts.on("--matrix", "Run every covering test per mutant and list blind and redundant tests") do
        set(:matrix, true)
      end
    end

    def define_output_options(opts)
      opts.on("--score-history PATH", "Append score history JSONL (opt-in)") { |v| set(:score_history, v) }
      opts.on("--json PATH", "Stryker JSON report path") { |v| set(:json_report, v) }
      opts.on("--html PATH", "Self-contained HTML report path") { |v| set(:html_report, v) }
      opts.on("--format FORMAT", %w[text agent], "text (default) or agent: one bounded JSON summary on stdout, " \
                                                 "strict exit codes") { |v| @format = v }
      opts.on("--agent", "Same as --format agent") { @format = "agent" }
      opts.on("--verbose", "Text report: also print score split, timings and kill causes") { @verbose = true }
      opts.on("--[no-]color", "Colour the text report (default: on for a terminal unless NO_COLOR is set)") do |v|
        @color = v ? :always : :never
      end
    end

    def define_explicit_file_options(opts)
      opts.on("--test PATH", "Spec file or directory to run; repeatable. Replaces the configured spec paths") do |v|
        (options[:tests] ||= []) << v
      end
      opts.on("--threshold PERCENT", Float, "Exit 1 when the score is below PERCENT (0-100)") do |v|
        set(:threshold, v)
      end
      Gates.define_options(opts) { |key, value| set(key, value) }
    end

    def add_subject(expr)
      (options[:subjects] ||= []) << expr
    end

    def set(key, value)
      options[key] = value
    end
  end
end
