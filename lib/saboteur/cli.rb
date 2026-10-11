# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "optparse"
require_relative "../saboteur"

module Saboteur
  class CLI
    USAGE = "Usage: saboteur run [SOURCE...] [--test TEST...] [--threshold PERCENT] [--since REF] " \
            "[--subject 'Klass#meth'] [--timeout-factor N] [--jobs N] [--seed N]"

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
      use_explicit_sources

      report = Engine.new(config, err: @err).call
      @err.puts
      Reporter::Terminal.new(@out).call(report)
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

      options[:include] = @argv.map { |source| source_pattern(source) }
      options[:exclude] = []
      options[:tests]&.each { |test| require_existing_test(test) }
    end

    def source_pattern(source)
      return "#{source.chomp('/')}/**/*.rb" if File.directory?(source)
      raise UsageError, "source is not a Ruby file: #{source}" if File.file?(source) && !source.end_with?(".rb")
      raise UsageError, "source file not found: #{source}" unless File.file?(source)

      source
    end

    # A test may carry an example selector: spec/a_spec.rb:12 or spec/a_spec.rb[1:2].
    def require_existing_test(test)
      path = test.sub(/(:\d+|\[[\d:]+\])+\z/, "")
      raise UsageError, "test file not found: #{test}" unless File.exist?(path)
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
        add_explicit_file_options(opts)
        opts.on("--config PATH", "Config file (default .saboteur.yml)") { |v| set(:config, v) }
        opts.on("--integration NAME", "Test adapter (rspec)") { |v| set(:integration, v) }
        opts.on("--reeval STRATEGY", Execution::Reevaluator::STRATEGIES, "class_eval or nesting") { |v| set(:reeval, v) }
        add_report_options(opts)
        opts.on("--no-cache", "Rebuild the coverage map") { set(:cache, false) }
        opts.on("--incremental", "Reuse earlier verdicts whose inputs did not change") { set(:incremental, true) }
      end
    end

    def add_report_options(opts)
      opts.on("--json PATH", "Stryker JSON report path") { |v| set(:json_report, v) }
      opts.on("--html PATH", "Self-contained HTML report path") { |v| set(:html_report, v) }
    end

    def add_explicit_file_options(opts)
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
