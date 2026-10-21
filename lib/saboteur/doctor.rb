# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require_relative "baseline_health"
require_relative "engine/sandbox_policy"
require_relative "execution/sandbox"

module Saboteur
  # Reports the current environment, never mutations. The two unchanged suite
  # passes are slow on a large suite, so they run only when asked for.
  class Doctor
    # One summary check: glyph status, one-line detail, exact fix (#333).
    Check = Data.define(:status, :detail, :fix) do
      def initialize(status:, detail:, fix: nil) = super
    end

    def initialize(config, out: $stdout, suite: false, verbose: true, palette: nil)
      @config = config
      @out = out
      @suite = suite
      @verbose = verbose
      @palette = palette || Reporter::Palette.for(out)
    end

    def call
      Engine::Boot.refuse_recursion!
      check_runtime
      check_environment
      check_coverage
      check_boot_files
      check_custom_map
      check_ignore_subjects
      hooks = Hooks.new
      integration = boot_target(hooks)
      @out.puts "Integration: #{@config['integration']} (loaded)"
      @out.puts "Rails: #{@config['rails'] ? 'enabled' : 'disabled'}"
      check_database_hosts
      @out.puts "SimpleCov: #{defined?(::SimpleCov) ? 'present; start suppressed for this process' : 'not loaded'}"
      verify_coverage
      check_sandbox
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

    def check_environment
      hints = EnvironmentHints.all(@config.root)
      @out.puts "Environment: #{hints.empty? ? 'no bundler/appraisal problems detected' : hints.join('; ')}"
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

    # Printed once; verified twice. Boot must not wake coverage up, so the
    # post-boot check re-reads the state without printing a second line.
    def check_coverage
      state = Coverage.state
      @out.puts "Coverage: #{state}"
      verify_coverage(state)
    end

    def verify_coverage(state = Coverage.state)
      return if Coverage.supported?(:lines) && Coverage.supported?(:methods) && state == :suspended

      raise Error, "Coverage must be suspended with line and method support before boot; use the saboteur " \
                   "executable, disable SimpleCov and remove other Coverage.start calls"
    end

    # A kernel capability probe, not verified isolation: what the kernel
    # would let mutant children do, and what the run does with that - the
    # engine's sandbox policy owns the refusal or degradation itself.
    def check_sandbox
      if @config["sandbox"] == false
        @out.puts "Sandbox: off (c.sandbox = false)"
        return
      end
      abi = sandbox_abi
      if abi >= 3
        @out.puts "Sandbox: kernel Landlock ABI #{abi} - capability probe only, not verified isolation"
      elsif @config["sandbox"] == "strict"
        @out.puts "Sandbox: #{Engine::SandboxPolicy.sandbox_gap(abi)}; " \
                  'c.sandbox = "strict" refuses to run - children never run degraded'
      else
        @out.puts "Sandbox: #{Engine::SandboxPolicy.sandbox_gap(abi)}; " \
                  "children would run with the hazard guard and canary only"
        if RUBY_PLATFORM.match?(/darwin/i) && @config["sandbox"] == "seatbelt"
          @out.puts %(Seatbelt (opt-in, #436): probe #{Execution::Seatbelt.probe} - capability probe only, ) \
                    "not verified isolation"
        elsif RUBY_PLATFORM.match?(/darwin/i)
          # Point at the way OUT of the degraded state, like the run
          # warning does (#667): the opt-in Seatbelt sandbox, or silence.
          @out.puts "macOS: mutants run unsandboxed (Landlock is Linux-only) - a container contains " \
                    "filesystem writes outside the project"
          @out.puts %(macOS: opt into the sandbox with c.sandbox = "seatbelt" ) \
                    "(docs/guides/macos-seatbelt-sandbox.md), or set c.sandbox = false to silence this"
          @out.puts "Network: never restricted on any platform, and a plain container keeps outbound " \
                    "access - deny or stub the network when a mutant could reach real APIs"
        end
      end
    end

    # The probe contract the engine's policy already keeps: an errored probe
    # (EPERM under a seccomp policy, ...) is an actionable tool error, not a
    # CLI internal error - doctor stays read-only.
    def sandbox_abi
      Execution::Sandbox.abi_version
    rescue SystemCallError => e
      raise Error, "sandbox is on but the Landlock probe failed (#{e.message}); a run would refuse the same way - " \
                   "set c.sandbox = false to check without the sandbox"
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

    # Prints the test database hosts the booted app reports, so a non-local
    # refusal names the host here instead of only at target boot (issue #258).
    def check_database_hosts
      return unless @config["rails"]
      return @out.puts("Databases: ActiveRecord did not load; host check skipped") unless defined?(::ActiveRecord::Base)

      configs = ::ActiveRecord::Base.configurations.configs_for(env_name: "test")
      configs.each do |db|
        host = db.configuration_hash[:host]
        @out.puts "Database: #{db.name} (host #{host.to_s.empty? ? 'local socket' : host})"
      end
      remote = Frameworks::Rails.remote_databases(configs, @config["allow_db_hosts"])
      return if remote.empty?

      raise ConfigError, "non-local test databases: #{remote.join(', ')}; if they are disposable test databases, " \
                         "allow them with c.allow_db_hosts in #{Config::FILE}"
    end

    def check_boot_files
      %w[require hooks].each do |key|
        @config[key].each do |file|
          path = File.expand_path(file, @config.root)
          # Resolve the way Kernel#require does: the path as given, or with
          # .rb appended (the Rails quickstart sets ./config/environment, issue #257).
          unless File.file?(path) || File.file?("#{path}.rb")
            raise ConfigError, "#{key} file missing: #{file}; fix config/saboteur.rb"
          end

          @out.puts "#{key}: #{file} (found)"
        end
      end
      @config.unmatched_patterns.each { |pattern| @out.puts "Warning: #{pattern} matches no file" }
    end
  end
end
