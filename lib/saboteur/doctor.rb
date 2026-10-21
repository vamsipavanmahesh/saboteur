# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require "stringio"
require_relative "baseline_health"
require_relative "engine/sandbox_policy"
require_relative "execution/sandbox"
require_relative "reporter/palette"

module Saboteur
  # Reports the current environment, never mutations. The default output is
  # a flutter-doctor style summary (#333): one line per check, every failure
  # or warning ending in the exact fix. `saboteur doctor -v` keeps the full
  # fact listing. The two unchanged suite passes are slow on a large suite,
  # so they run only when asked for.
  class Doctor
    # One summary line: its glyph token, the finding, and the exact fix when
    # the check is not green.
    Check = Data.define(:status, :detail, :fix) do
      def initialize(status:, detail:, fix: nil) = super
    end

    # Spec helpers scanned for an unguarded SimpleCov.start (#312).
    SIMPLECOV_HELPERS = %w[spec/spec_helper.rb spec/rails_helper.rb].freeze

    def initialize(config, out: $stdout, suite: false, verbose: false, palette: nil)
      @config = config
      @out = out
      @suite = suite
      @verbose = verbose
      @palette = palette || Reporter::Palette.for(out)
    end

    # True when nothing failed; the CLI turns a false summary into exit 1.
    def call
      Engine::Boot.refuse_recursion!
      return summary_call unless @verbose

      verbose_call
      true
    end

    private

    # The summary shape: compute every check first - config, boot and
    # coverage failures keep the detail listing's raises and exit 2/3 -
    # then print one line per check. Golden order: runtime, suite, the
    # environment warning when present, then the remaining checks.
    def summary_call
      early = [runtime_check, environment_check, simplecov_guard_check].compact
      boot_silently
      late = [sandbox_check, ignore_health_check].compact
      suite = @suite ? [suite_check] : []
      checks = [early.first] + suite + early.drop(1) + late
      render_summary(checks)
      checks.none? { |check| check.status == :fail }
    end

    # Boot and the config validations keep the detail listing's behaviour,
    # including its ConfigError/Error raises; only the per-file chatter is
    # swallowed - the summary renders one line per check, not per file.
    def boot_silently
      original = @out
      @out = StringIO.new
      check_boot_files
      check_custom_map
      @hooks = Hooks.new
      @integration = boot_target(@hooks)
      check_database_hosts
      verify_coverage
    ensure
      @out = original
    end

    def runtime_check
      runtime_guard
      version = rspec_version
      unless version
        return Check.new(status: :fail, detail: "RSpec not found - the rspec integration cannot load",
                         fix: "bundle install, or add rspec to your Gemfile")
      end

      middot = @palette.glyph(:middot)
      bundler = environment_hints.empty? ? " #{middot} bundler ok" : ""
      Check.new(status: :pass, detail: "Ruby #{RUBY_VERSION} #{middot} RSpec #{version}#{bundler}")
    end

    def rspec_version
      require "rspec/core/version"
      ::RSpec::Core::Version::STRING
    rescue LoadError
      nil
    end

    def environment_check
      return nil if environment_hints.empty?

      Check.new(status: :warn, detail: "environment: #{environment_hints.join('; ')}",
                fix: "address the environment hints, then re-run saboteur doctor")
    end

    def environment_hints
      @environment_hints ||= EnvironmentHints.all(@config.root)
    end

    # A SimpleCov.start that fires on every spec run steals method coverage
    # from saboteur's own map; it must load only when COVERAGE is set (#312).
    def simplecov_guard_check
      SIMPLECOV_HELPERS.each do |relative|
        path = File.join(@config.root, relative)
        next unless File.file?(path)

        lines = File.readlines(path)
        start = lines.index { |line| line.match?(/^\s*SimpleCov\.start/) }
        next unless start
        if lines.any? { |line| line.match?(/ENV\[["']COVERAGE["']\]/) }
          return Check.new(status: :pass, detail: %(SimpleCov: guarded by ENV["COVERAGE"]))
        end

        return Check.new(status: :fail,
                         detail: "SimpleCov is not guarded - it steals coverage from saboteur",
                         fix: %(wrap it: if ENV["COVERAGE"]  (#{relative}:#{start + 1})))
      end
      nil
    end

    # One line on the ignore file's health: how many entries, and how many
    # name a subject no included file defines anymore (feeds PR15's prune).
    def ignore_health_check
      ignores = IgnoreList.load(@config.path("ignore_file"))
      return nil if ignores.entries.empty?

      stale = stale_ignore_subjects(ignores)
      if stale == :parse_error
        return Check.new(status: :warn,
                         detail: "ignore file: health check incomplete - an included file does not parse",
                         fix: "fix the parse error, then re-run saboteur doctor")
      end

      total = ignores.entries.size
      if stale.empty?
        return Check.new(status: :pass,
                         detail: "ignore file: #{total} #{total == 1 ? 'entry' : 'entries'}, all live")
      end

      Check.new(status: :warn, detail: "ignore file: #{total} entries, #{stale.size} stale",
                fix: "remove or refresh the stale entries in #{@config['ignore_file']}")
    end

    # The probe contract the detail listing keeps: an errored probe is an
    # actionable tool error, not a crash - doctor stays read-only.
    def sandbox_check
      return nil if @config["sandbox"] == false

      abi = sandbox_abi
      return Check.new(status: :pass, detail: "sandbox: Landlock ABI #{abi}") if abi >= 3

      if @config["sandbox"] == "strict"
        return Check.new(status: :fail,
                         detail: %(sandbox: #{sandbox_gap_detail(abi)} - c.sandbox = "strict" refuses to run),
                         fix: "kernel 6.2+ for full isolation, or set c.sandbox = true to run degraded")
      end
      if Execution::Seatbelt.darwin?
        return Check.new(status: :warn, detail: "sandbox: macOS has no Landlock - mutants run unsandboxed",
                         fix: %(opt in with c.sandbox = "seatbelt", or run inside a container))
      end

      Check.new(status: :warn,
                detail: "sandbox: #{sandbox_gap_detail(abi)} - children run with the hazard guard only",
                fix: "kernel 6.2+ for full isolation, or accept reduced isolation")
    end

    def sandbox_gap_detail(abi)
      abi.zero? ? "no Landlock (needs Linux 6.2+)" : "Landlock ABI #{abi} < 3"
    end

    def suite_check
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tests = BaselineHealth.new(@config, integration: @integration, hooks: @hooks).call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      Check.new(status: :pass, detail: "unchanged suite green (#{tests.size} examples, #{format_seconds(elapsed)})")
    end

    # 0.3s under ten seconds, 14s past it - no trailing ".0".
    def format_seconds(value)
      rounded = value.round(1)
      "#{rounded == rounded.to_i ? rounded.to_i : rounded}s"
    end

    def render_summary(checks)
      @out.puts "Doctor summary (details: saboteur doctor -v):"
      checks.each do |check|
        @out.puts @palette.paint(check.status, "#{summary_glyph(check.status)} #{check.detail}")
        @out.puts "    Fix: #{check.fix}" if check.fix
      end
      return unless checks.any? { |check| check.status == :fail }

      @out.puts @palette.paint(:fail, "exit 1 - fix the #{@palette.glyph(:cross)} above before trusting a run")
    end

    def summary_glyph(status)
      { pass: @palette.glyph(:check), fail: @palette.glyph(:cross), warn: "!" }.fetch(status)
    end

    # The full fact listing (`saboteur doctor -v`): the pre-summary report,
    # unchanged.
    def verbose_call
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
    end

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
      hints = environment_hints
      @out.puts "Environment: #{hints.empty? ? 'no bundler/appraisal problems detected' : hints.join('; ')}"
    end

    def check_runtime
      runtime_guard
      @out.puts "Ruby: #{RUBY_DESCRIPTION}"
    end

    def runtime_guard
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

      stale = stale_ignore_subjects(ignores)
      if stale == :parse_error
        @out.puts "Warning: ignore subject check incomplete: an included file does not parse"
        return
      end
      stale.each do |subject|
        @out.puts "Warning: ignore subject #{subject} matches no discovered subject in included files; " \
                  "check include/exclude settings and the exact Class#method or Class.method form"
      end
    end

    # The ignore subjects no included file defines, or :parse_error when a
    # file does not parse and the check cannot be trusted.
    def stale_ignore_subjects(ignores)
      finder = SubjectFinder.new
      parsed = @config.included_files.map { |file| finder.call(file) }
      return :parse_error if parsed.any? { |result| result.errors.any? }

      subjects = parsed.flat_map(&:subjects).to_set(&:id)
      ignores.entries.map(&:subject).uniq.reject { |subject| subjects.include?(subject) }
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
