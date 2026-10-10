# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "optparse"
require_relative "../saboteur"

module Saboteur
  class CLI
    USAGE = "Usage: saboteur run [--since REF] [--subject 'Klass#meth'] [--timeout-factor N] [--jobs N] [--seed N]"

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
      when "run" then run
      when "version", "--version" then @out.puts(VERSION) || EXIT_OK
      else usage_error
      end
    rescue OptionParser::ParseError => e
      usage_error(e.message)
    end

    def config
      @config ||= Config.load(root: Dir.pwd, path: options[:config], overrides: overrides)
    end

    private

    def usage_error(message = nil)
      @err.puts(message) if message
      @err.puts(USAGE)
      EXIT_USAGE
    end

    def run
      parser.parse!(@argv)
      raise UsageError, "unexpected arguments: #{@argv.join(' ')}" if @argv.any?

      report = Engine.new(config, err: @err).call
      @err.puts
      Reporter::Terminal.new(@out).call(report)
      write_json(report)
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

    def exit_code(report)
      executed = report.executed
      return EXIT_TOOL if executed.any? && executed.all? { |result| result.status == :error }

      report.unignored_survivors.any? ? EXIT_SURVIVORS : EXIT_OK
    end

    def overrides
      options.except(:config)
    end

    def parser
      OptionParser.new do |opts|
        opts.banner = USAGE
        opts.on("--since REF", "Only mutate subjects changed since git REF") { |v| options[:since] = v }
        opts.on("--subject EXPR", "Klass#meth, Klass.meth or a namespace; repeatable") { |v| add_subject(v) }
        opts.on("--timeout-factor N", Float, "Multiple of baseline runtime (default 3)") { |v| set(:timeout_factor, v) }
        opts.on("--jobs N", Integer, "Concurrent workers (default 1)") { |v| set(:jobs, v) }
        opts.on("--seed N", Integer, "Seed for Ruby's random numbers in every test run (default 1)") do |v|
          set(:seed, v)
        end
        opts.on("--config PATH", "Config file (default .saboteur.yml)") { |v| set(:config, v) }
        opts.on("--integration NAME", "Test adapter (rspec)") { |v| set(:integration, v) }
        opts.on("--reeval STRATEGY", Execution::Reevaluator::STRATEGIES, "class_eval or nesting") { |v| set(:reeval, v) }
        opts.on("--json PATH", "Stryker JSON report path") { |v| set(:json_report, v) }
        opts.on("--no-cache", "Rebuild the coverage map") { set(:cache, false) }
        opts.on("--incremental", "Reuse earlier verdicts whose inputs did not change") { set(:incremental, true) }
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
