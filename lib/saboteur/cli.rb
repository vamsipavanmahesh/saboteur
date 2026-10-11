# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "optparse"
require_relative "../saboteur"
require_relative "doctor"
require_relative "help"
require_relative "reporter/replay"

module Saboteur
  class CLI
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
      when "run" then help_requested? ? show_help("run") : run
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
      { "run" => parser.summarize, "doctor" => doctor_parser.summarize }
    end

    def doctor_parser
      OptionParser.new do |opts|
        opts.banner = "Usage: saboteur doctor [--config PATH] [--seed N]"
        opts.on("--config PATH", "Config file (default .saboteur.yml)") { |value| set(:config, value) }
        opts.on("--seed N", Integer, "Seed for the two baseline runs (default 1)") { |value| set(:seed, value) }
      end
    end

    private

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

    # Agent mode has one strict meaning for exit 0, so a score threshold cannot also decide it.
    def reject_threshold_with_agent_format
      return unless agent? && config["threshold"]

      raise UsageError, "--threshold cannot be combined with --agent: agent mode exits 0 only for a complete, clean run"
    end

    def text_run(report)
      @err.puts
      Reporter::Terminal.new(@out).call(report)
      Reporter::Replay.new(@out).call(report) if options[:id]
      write_json(report)
      write_html(report)
      exit_code(report)
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
      tree = WorkingTree.new(config.root, ignored: output_paths).state
      report = stdout_on_stderr { Engine.new(config, **arguments).call }
      write_json(report, announce: false)
      write_html(report, announce: false)
      payload = Reporter::Agent.call(report, agent_provenance(report, tree))
      @out.print(Reporter::Agent.render(payload))
      Reporter::Agent.exit_code(payload)
    end

    # Paths of saboteur's own output, relative to the root, that do not count as source changes.
    def output_paths
      root = File.join(File.realpath(config.root), "")
      %w[cache_dir json_report html_report].filter_map { |key| config.path(key) }
                                           .map { |path| File.expand_path(path) }
                                           .select { |path| path.start_with?(root) }
                                           .map { |path| path.delete_prefix(root) }
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

    def agent_provenance(report, tree)
      Reporter::Agent::Provenance.new(
        ref: config["since"], seed: report.seed, head: tree.head, working_tree: tree.label,
        changed_files: tree.changed_files, mode: agent_mode, json_report: config.path("json_report"),
        subjects: Array(config["subjects"]), tests: Array(options[:tests]), sources: @sources || [],
        config_path: options[:config], digest: options[:id], cache: config["cache"],
        incremental: config["incremental"], settings: options.slice(*Reporter::Agent::Commands::SETTING_FLAGS.keys)
      )
    end

    def agent_mode
      return "replay" if options[:id]
      return "diff" if config["since"]

      @sources&.any? ? "files" : "full"
    end

    def write_json(report, announce: true)
      path = config.path("json_report")
      return unless path

      Reporter::Stryker.new(path).call(report)
      @out.puts "\nJSON report: #{path}" if announce
    end

    def write_html(report, announce: true)
      path = config.path("html_report")
      return unless path

      Reporter::Html.new(path).call(report)
      @out.puts "HTML report: #{path}" if announce
    end

    def exit_code(report)
      executed = report.executed
      return EXIT_TOOL if executed.any? && executed.all? { |result| result.status == :error }

      return EXIT_TOOL if incomplete_under_threshold?(report)

      failed_quality_gate?(report) ? EXIT_SURVIVORS : EXIT_OK
    end

    # With --threshold the score decides; without it any unignored survivor does.
    def failed_quality_gate?(report)
      threshold = config["threshold"]
      return report.unignored_survivors.any? if threshold.nil?

      score = report.score
      return missing_score_reported? if score.nil?

      score * 100 < threshold
    end

    # A gate that cannot measure a score must not pass: CI would go green
    # on a run that tested nothing.
    def missing_score_reported?
      @err.puts("saboteur: no mutant was tested, so there is no score to compare with --threshold")
      true
    end

    # Errors and resource limits are outside the score. With a threshold they
    # make the run incomplete, so the score alone cannot pass it.
    def incomplete_under_threshold?(report)
      return false if config["threshold"].nil?

      count = report.counts.values_at(:error, :resource_limit).sum
      @err.puts("saboteur: #{count} mutant(s) errored or hit a resource limit, so the score is incomplete") if
        count.positive?
      count.positive?
    end

    # Positional arguments name the files (or directories) to mutate. They
    # replace the configured include and exclude patterns. Each must exist,
    # so a typo is an error and not a run over zero subjects.
    def use_explicit_sources
      raise UsageError, "--test needs at least one source file" if options[:tests] && @argv.empty?
      return if @argv.empty?

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
      options.except(:config, :id)
    end

    def define_selection_options(opts)
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
      opts.on("--config PATH", "Config file (default .saboteur.yml)") { |v| set(:config, v) }
      opts.on("--integration NAME", "Test adapter (rspec)") { |v| set(:integration, v) }
      opts.on("--reeval STRATEGY", Execution::Reevaluator::STRATEGIES, "class_eval or nesting") { |v| set(:reeval, v) }
      opts.on("--no-cache", "Rebuild the coverage map") { set(:cache, false) }
      opts.on("--incremental", "Reuse earlier verdicts whose inputs did not change") { set(:incremental, true) }
    end

    def define_output_options(opts)
      opts.on("--json PATH", "Stryker JSON report path") { |v| set(:json_report, v) }
      opts.on("--html PATH", "Self-contained HTML report path") { |v| set(:html_report, v) }
      opts.on("--format FORMAT", %w[text agent], "text (default) or agent: one bounded JSON summary on stdout, " \
                                                 "strict exit codes") { |v| @format = v }
      opts.on("--agent", "Same as --format agent") { @format = "agent" }
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
