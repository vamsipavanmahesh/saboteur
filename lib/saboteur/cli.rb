# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "optparse"
require_relative "../saboteur"
require_relative "help"
require_relative "reporter/replay"

module Saboteur
  class CLI
    USAGE = "Usage: saboteur run [--since REF] [--subject 'Klass#meth'] [--timeout-factor N] " \
            "[--jobs N] [--seed N] [--id DIGEST]\n" \
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
    end

    def call
      case @argv.shift
      when "run" then help_requested? ? show_help("run") : run
      when "version", "--version" then @out.puts(VERSION) || EXIT_OK
      when "help" then show_help(@argv.shift)
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
        define_execution_options(opts)
        define_output_options(opts)
      end
    end

    # The parser's option lines, as printed under OPTIONS in `saboteur help`.
    def option_lines
      parser.summarize
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
      EXIT_USAGE
    end

    def run
      parser.parse!(@argv)
      raise UsageError, "unexpected arguments: #{@argv.join(' ')}" if @argv.any?

      arguments = { err: @err }
      arguments[:digest] = options[:id] if options[:id]
      report = Engine.new(config, **arguments).call
      @err.puts
      Reporter::Terminal.new(@out).call(report)
      Reporter::Replay.new(@out).call(report) if options[:id]
      write_json(report)
      write_html(report)
      exit_code(report)
    rescue ConfigError => e
      @err.puts("saboteur: #{e.message}")
      EXIT_USAGE
    rescue Error => e
      @err.puts("saboteur: #{e.message}")
      EXIT_TOOL
    end

    def write_json(report)
      path = config.path("json_report")
      return unless path

      Reporter::Stryker.new(path).call(report)
      @out.puts "\nJSON report: #{path}"
    end

    def write_html(report)
      path = config.path("html_report")
      return unless path

      Reporter::Html.new(path).call(report)
      @out.puts "HTML report: #{path}"
    end

    def exit_code(report)
      executed = report.executed
      return EXIT_TOOL if executed.any? && executed.all? { |result| result.status == :error }

      report.unignored_survivors.any? ? EXIT_SURVIVORS : EXIT_OK
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
    end

    def add_subject(expr)
      (options[:subjects] ||= []) << expr
    end

    def set(key, value)
      options[key] = value
    end
  end
end
