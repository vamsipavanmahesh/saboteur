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

module Saboteur
  class CLI
    include Baseline::Command
    include ExitStatus

    USAGE = "Usage: saboteur run [SOURCE...] [--test TEST...] [--threshold PERCENT] [--since REF] " \
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
        define_output_options(opts)
      end
    end

    # Each command's own option lines, as printed under OPTIONS in `saboteur help`.
    def option_lines
      { "run" => parser.summarize, "doctor" => doctor_parser.summarize, "baseline" => baseline_parser.summarize }
    end

    def doctor_parser
      OptionParser.new do |opts|
        opts.banner = "Usage: saboteur doctor [--config PATH] [--seed N]"
        opts.on("--config PATH", "Config file (default config/saboteur.rb)") { |value| set(:config, value) }
        opts.on("--seed N", Integer, "Seed for the two baseline runs (default 1)") { |value| set(:seed, value) }
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
      use_explicit_sources
      reject_threshold_with_agent_format
      warn_dirty_tree

      return preview if options[:list_operators] || options[:dry_run]

      arguments = { err: @err }
      arguments[:digest] = options[:id] if options[:id]
      agent? ? agent_run(arguments) : text_run(Engine.new(config, **arguments).call)
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

    # Agent mode has one strict meaning for exit 0, so a score threshold cannot also decide it.
    def reject_threshold_with_agent_format
      return unless agent? && config["threshold"]

      raise UsageError, "--threshold cannot be combined with --agent: agent mode exits 0 only for a complete, clean run"
    end

    def text_run(report)
      @err.puts
      Reporter::Terminal.new(@out, verbose: @verbose || false, color: @color || :auto).call(report)
      Reporter::Replay.new(@out).call(report) if options[:id]
      code = exit_code(report)
      # The JSON carries the exit cause an outer harness trusts, so it is
      # the completion evidence for the whole run: write it only after
      # every other fallible reporting stage, or a late failure would
      # leave a fresh, misleading report behind.
      write_html(report)
      write_json(report, exit_cause(report, code))
      code
    end

    def doctor
      doctor_parser.parse!(@argv)
      raise UsageError, "unexpected arguments: #{@argv.join(' ')}" if @argv.any?

      Doctor.new(config, out: @out).call
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
    def agent_run(arguments)
      tree = WorkingTree.new(config.root, ignored: config.output_paths).state
      engine = Engine.new(config, **arguments)
      report = stdout_on_stderr { engine.call }
      payload = Reporter::Agent.call(report, agent_provenance(report, tree, engine))
      rendered = Reporter::Agent.render(payload)
      # Same publish order as text_run: the JSON is the completion
      # evidence, so it is written only after every other fallible stage,
      # including the agent payload itself.
      write_html(report, announce: false)
      write_json(report, agent_exit_cause(report, payload), announce: false)
      @out.print(rendered)
      Reporter::Agent.exit_code(payload)
    end

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
        subjects: Array(config["subjects"]), tests: Array(engine.guessed_tests || options[:tests]),
        sources: @sources || [],
        config_path: options[:config], digest: options[:id], cache: config["cache"],
        incremental: config["incremental"], settings: options.slice(*Reporter::Agent::Commands::SETTING_FLAGS.keys)
      )
    end

    def agent_mode
      return "replay" if options[:id]
      return "diff" if config["since"]

      @sources&.any? ? "files" : "full"
    end

    def write_json(report, cause, announce: true)
      path = config.path("json_report")
      return unless path

      Reporter::Stryker.new(path).call(report, exit_cause: cause)
      @out.puts "\nJSON report: #{path}" if announce
    end

    def write_html(report, announce: true)
      path = config.path("html_report")
      return unless path

      Reporter::Html.new(path).call(report)
      @out.puts "HTML report: #{path}" if announce
    end

    # Positional arguments name the files (or directories) to mutate. They
    # replace the configured include and exclude patterns. Each must exist,
    # so a typo is an error and not a run over zero subjects.
    def use_explicit_sources
      if @argv.empty?
        raise UsageError, "--test needs at least one source file" if options[:tests] && !config["since"]

        # With --since the changed files are the sources, so --test may
        # stand alone; the files must still exist.
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
      options.except(:config, :id, :list_operators, :dry_run)
    end

    def preview
      raise UsageError, "--dry-run and --list-operators print text, not --agent JSON" if agent?
      raise UsageError, "--id replays one mutant: not with --dry-run or --list-operators" if options[:id]

      return MutationSource::OperatorRegistry.list(@out) || EXIT_OK if options[:list_operators]

      Preview.new(config, out: @out, err: @err).call
      EXIT_OK
    end

    def define_selection_options(opts)
      opts.on("--operators NAMES", Array, "Choose operator names or tiers (core, extended, all)") do |v|
        set(:operators, v)
      end
      opts.on("--list-operators", "List operator names, descriptions and tiers") { set(:list_operators, true) }
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
      opts.on("--[no-]guess-tests", "With --since: run only the specs named after the changed files " \
                                    "(lib/a.rb -> spec/a_spec.rb); the whole suite if any has none") do |v|
        set(:guess_tests, v)
      end
    end

    def define_output_options(opts)
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
    end

    def add_subject(expr)
      (options[:subjects] ||= []) << expr
    end

    def set(key, value)
      options[key] = value
    end
  end
end
