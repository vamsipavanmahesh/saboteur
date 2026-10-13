# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require_relative "baseline_health"

module Saboteur
  # Reports the current environment, never mutations. The two unchanged suite
  # passes are slow on a large suite, so they run only when asked for.
  class Doctor
    def initialize(config, out: $stdout, suite: false)
      @config = config
      @out = out
      @suite = suite
    end

    def call
      Engine::Boot.refuse_recursion!
      check_runtime
      check_coverage
      check_boot_files
      check_custom_map
      check_ignore_subjects
      hooks = Hooks.new
      integration = boot_target(hooks)
      @out.puts "Integration: #{@config['integration']} (loaded)"
      @out.puts "Rails: #{@config['rails'] ? 'enabled' : 'disabled'}"
      @out.puts "SimpleCov: #{defined?(::SimpleCov) ? 'present; start suppressed for this process' : 'not loaded'}"
      check_coverage
      check_suite(integration, hooks)
      true
    end

    private

    def check_suite(integration, hooks)
      unless @suite
        @out.puts "Baseline: not run. Pass --suite to run the unchanged suite twice " \
                  "(add --test PATH to limit it to some specs)."
        return
      end

      tests = BaselineHealth.new(@config, integration: integration, hooks: hooks).call
      @out.puts "Baseline: #{tests.size} tests passed twice in the same order with seed #{@config['seed']}"
      @out.puts "Healthy in these two runs. This does not prove the suite is free of flaky tests."
    end

    def boot_target(hooks)
      Engine::Boot.new(@config, hooks).load_target
    rescue LoadError, SyntaxError, SystemExit, StandardError => e
      raise Error, "target boot failed: #{e.class}: #{e.message}; check require files, hooks and rspec_args"
    end

    def check_runtime
      @out.puts "Ruby: #{RUBY_DESCRIPTION}"
      unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3") && Process.respond_to?(:fork)
        raise Error, "doctor needs Ruby 3.3+ with fork; use supported Ruby on Linux or macOS"
      end
      return if @config["integration"] == "rspec"

      raise ConfigError,
            "doctor supports the rspec integration; set integration: rspec"
    end

    def check_coverage
      state = Coverage.state
      @out.puts "Coverage: #{state}"
      return if Coverage.supported?(:lines) && Coverage.supported?(:methods) && state == :suspended

      raise Error, "Coverage must be suspended with line and method support before boot; use the saboteur " \
                   "executable, disable SimpleCov and remove other Coverage.start calls"
    end

    # Match against all included source definitions, not the current diff or
    # selected tests. A limited run must not make a valid ignore look stale.
    def check_ignore_subjects
      ignores = IgnoreList.load(@config.path("ignore_file"))
      return if ignores.entries.empty?

      finder = SubjectFinder.new
      parsed = @config.included_files.map { |file| finder.call(file) }
      if parsed.any? { |result| result.errors.any? }
        @out.puts "Warning: ignore subject check incomplete: an included file does not parse"
        return
      end
      subjects = parsed.flat_map(&:subjects).to_set(&:id)
      ignores.entries.map(&:subject).uniq.reject { |subject| subjects.include?(subject) }.each do |subject|
        @out.puts "Warning: ignore subject #{subject} matches no discovered subject in included files; " \
                  "check include/exclude settings and the exact Class#method or Class.method form"
      end
    end

    def check_custom_map
      path = @config.path("custom_map")
      map = CustomMap.load(path, root: @config.root)
      return @out.puts("Custom map: none (optional)") if map.empty?

      duplicates = map.duplicate_keys(path)
      if duplicates.any?
        @out.puts "Warning: custom map keys written twice, Ruby keeps the last: #{duplicates.join(', ')}"
      end
      stale = map.stale_keys
      raise ConfigError, "#{path}: stale keys matching no file: #{stale.join(', ')}" if stale.any?

      @out.puts "Custom map: #{map.entries.size} entries (loaded)"
    end

    def check_boot_files
      %w[require hooks].each do |key|
        @config[key].each do |file|
          path = File.expand_path(file, @config.root)
          raise ConfigError, "#{key} file missing: #{file}; fix config/saboteur.rb" unless File.file?(path)

          @out.puts "#{key}: #{file} (found)"
        end
      end
      @config.unmatched_patterns.each { |pattern| @out.puts "Warning: #{pattern} matches no file" }
    end
  end
end
