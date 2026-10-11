# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require_relative "baseline_health"

module Saboteur
  # Reports the current environment and runs baseline checks, never mutations.
  class Doctor
    def initialize(config, out: $stdout)
      @config = config
      @out = out
    end

    def call
      Engine::Boot.refuse_recursion!
      check_runtime
      check_coverage
      check_boot_files
      hooks = Hooks.new
      integration = boot_target(hooks)
      @out.puts "Integration: #{@config['integration']} (loaded)"
      @out.puts "Rails: #{@config['rails'] ? 'enabled' : 'disabled'}"
      @out.puts "SimpleCov: #{defined?(::SimpleCov) ? 'present; start suppressed for this process' : 'not loaded'}"
      check_coverage
      tests = BaselineHealth.new(@config, integration: integration, hooks: hooks).call
      @out.puts "Baseline: #{tests.size} tests passed twice in the same order with seed #{@config['seed']}"
      @out.puts "Healthy in these two runs. This does not prove the suite is free of flaky tests."
      true
    end

    private

    def boot_target(hooks)
      Engine::Boot.new(@config, hooks).load_target
    rescue LoadError, StandardError => e
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
      return if Coverage.supported?(:lines) && state == :suspended

      raise Error, "Coverage must be suspended with line support before boot; use the saboteur executable, " \
                   "disable SimpleCov and remove other Coverage.start calls"
    end

    def check_boot_files
      %w[require hooks].each do |key|
        @config[key].each do |file|
          path = File.expand_path(file, @config.root)
          raise ConfigError, "#{key} file missing: #{file}; fix .saboteur.yml" unless File.file?(path)

          @out.puts "#{key}: #{file} (found)"
        end
      end
      @config.unmatched_patterns.each { |pattern| @out.puts "Warning: #{pattern} matches no file" }
    end
  end
end
