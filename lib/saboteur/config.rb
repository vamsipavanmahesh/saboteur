# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "text"

require_relative "mutation_source/builtin"
require_relative "mutation_source/operator_registry"
require_relative "mutation_source/hazard_guard"

module Saboteur
  # Settings from config/saboteur.rb, overridden by CLI flags.
  class Config
    FILE = "config/saboteur.rb"

    # Died with the YAML port: a leftover file means settings are
    # silently ignored, which could turn off a threshold. Fail loud.
    LEGACY_FILE = ".saboteur.yml"
    LEGACY_IGNORE_FILE = ".saboteur-ignore.yml"
    IGNORE_FILE = "config/saboteur_ignore.rb"

    # Settings that say where saboteur writes, never what it mutates: left
    # out of the run fingerprint, baseline evidence and score-history scope.
    OUTPUT_KEYS = %w[cache_dir json_report html_report score_history resume].freeze

    # Presentation-only settings: like OUTPUT_KEYS they never enter the run
    # fingerprint, baseline evidence or score-history scope, but they are
    # not paths.
    PRESENTATION_KEYS = %w[palette].freeze

    DEFAULTS = {
      "integration" => "rspec",
      "require" => [],
      "include" => ["lib/**/*.rb"],
      # Spec and test files vendored under lib/ (capybara ships its driver
      # suite at lib/capybara/spec/**) are never mutation subjects (#504).
      # A config's own c.exclude replaces this list wholesale.
      "exclude" => ["lib/**/spec/**/*", "lib/**/test/**/*", "lib/**/tests/**/*",
                    "lib/**/*_spec.rb", "lib/**/*_test.rb", "lib/**/test_*.rb"],
      "arid" => MutationSource::Builtin::DEFAULT_ARID,
      "whole_file" => [],
      # [{ "pattern" => "app/payments/**/*", "min_score" => 95.0 }], from
      # repeatable c.score_gate calls (#473). --threshold stays the global
      # fallback.
      "score_gates" => [],
      "hazard" => MutationSource::HazardGuard::DEFAULT_HAZARD,
      "allow_hazardous" => false,
      # true, false, "strict" or "seatbelt": strict refuses to run without full Landlock;
      # seatbelt opts into the macOS Seatbelt sandbox (on Linux it behaves like true).
      "sandbox" => true,
      "sandbox_writable" => [],
      # off, survivors, or decisive (#476): one reordered confirmation run
      # per new survivor (and per fresh kill in decisive); a disagreement
      # becomes unverified, outside the score.
      "flaky_check" => "off",
      "timeout_factor" => 3.0,
      "timeout_min" => 5.0,
      "baseline_timeout" => 300.0,
      "coverage_timeout" => 3600.0,
      "max_memory_mb" => 2048,
      "max_processes" => 64,
      "max_mutants_per_method" => 100,
      "jobs" => 1,
      "ignore_file" => "config/saboteur_ignore.rb",
      "custom_map" => "config/saboteur_custom_map.rb",
      "sources" => ["builtin"],
      "operators" => [],
      "exclude_operators" => [],
      "hooks" => [],
      "rails" => false,
      # Hosts the user asserts are disposable test databases (issue #258).
      "allow_db_hosts" => [],
      "reeval" => "nesting",
      "cache_dir" => ".saboteur",
      "json_report" => ".saboteur/report.json",
      "html_report" => ".saboteur/report.html",
      "score_history" => nil,
      "rspec_args" => [],
      "subjects" => [],
      "since" => nil,
      "cache" => true,
      # Experimental (#46): "shadow" also builds a partial coverage map after a
      # cache miss and compares it with the full map, which the run still uses.
      # "use" uses the partial map when it is safe and builds the full map otherwise.
      "partial_coverage" => "off",
      # Total seconds survivor confirmation may spend per run when
      # partial_coverage=use (#1063); the per-survivor spec cap is a constant.
      "confirmation_budget" => 300.0,
      # coverage (default) reads Coverage around every test; trace gets lines and
      # methods from a TracePoint and reads branches once per spec file (#725).
      "coverage_recorder" => "coverage",
      "incremental" => false,
      "resume" => nil,
      "shard" => nil,
      "allow_focus" => false,
      "fail_fast" => false,
      "guess_tests" => false,
      "all" => false,
      "test_selection" => "auto",
      "matrix" => false,
      "seed" => 1,
      "baseline_passes" => 2,
      # Parallel children for the coverage-map build (#741); 1 keeps the single child.
      "coverage_parts" => 1,
      "max_duration" => nil,
      "max_duration_ok" => false,
      "ignore_empty" => false,
      "baseline" => nil,
      "epsilon" => nil,
      "tests" => [],
      "test_command" => nil,
      "fingerprint_extra" => [],
      "threshold" => nil,
      "max_timeouts" => nil,
      "max_errors" => nil,
      # --verbose also lands here, so boot-time output filters (the rspec
      # load-error report, #608) can keep their raw text behind the flag.
      "verbose" => false,
      # Text-report colour overrides: token -> ANSI colour name, validated
      # against Reporter::Palette. Presentation only, never fingerprinted.
      "palette" => {}
    }.freeze

    INTEGER_KEYS = %w[jobs max_memory_mb max_processes max_mutants_per_method seed baseline_passes
                      coverage_parts].freeze
    FLOAT_KEYS = %w[timeout_factor timeout_min baseline_timeout coverage_timeout confirmation_budget].freeze
    STRING_KEYS = %w[test_selection partial_coverage coverage_recorder].freeze
    NILABLE_FLOAT_KEYS = %w[threshold max_duration].freeze
    THRESHOLD_RANGE = (0.0..100.0)

    LIST_KEYS = %w[require include exclude arid hazard sources hooks rspec_args subjects tests
                   fingerprint_extra sandbox_writable operators exclude_operators whole_file allow_db_hosts].freeze

    attr_reader :root

    def self.load(root: Dir.pwd, path: nil, overrides: {})
      path ||= File.join(root, FILE)
      legacy = File.join(root, LEGACY_FILE)
      if File.file?(legacy)
        raise ConfigError,
              "saboteur no longer reads #{LEGACY_FILE}; move its settings to #{FILE} (see README)."
      end
      legacy_ignore = File.join(root, LEGACY_IGNORE_FILE)
      if File.file?(legacy_ignore)
        raise ConfigError,
              "saboteur no longer reads #{LEGACY_IGNORE_FILE}; move its entries to #{IGNORE_FILE} (see README)."
      end

      from_file = File.file?(path) ? ConfigFile.load(path) : {}
      new(from_file.merge(stringify(overrides)), root: root, config_file_present: File.file?(path))
    end

    def self.stringify(hash)
      hash.to_h { |key, value| [key.to_s, value] }.compact
    end

    # Deprecations found while loading: printed by the CLI, never fatal.
    attr_reader :deprecation_warnings

    # Whether the config file existed at load (#1172): the CLI says once
    # when a run falls back to defaults because no file was there.
    attr_reader :config_file_present

    def initialize(values = {}, root: Dir.pwd, explicit: nil, config_file_present: true)
      # Retag the root losslessly: under a non-UTF-8 locale it arrives
      # locale-tagged, and every glob, join and expand below would mix
      # encodings with the UTF-8 patterns from the config file (#231).
      @root = Text.utf8_identity(File.expand_path(root))
      @config_file_present = config_file_present
      unknown = values.keys - DEFAULTS.keys
      raise ConfigError, "unknown config key(s): #{unknown.join(', ')}" if unknown.any?

      @deprecation_warnings = deprecations(values)
      @explicit_keys = (explicit || values.keys).map(&:to_s).freeze
      @values = DEFAULTS.merge(values)
      coerce!
      validate!
      validate_report_paths!
    end

    def [](key)
      @values.fetch(key.to_s)
    end

    def fetch(key, default = nil)
      @values.fetch(key.to_s, default)
    end

    # Keys the user set (config file or CLI flag) rather than relying on
    # the default; carried through Engine's config clone so provenance
    # survives (#296).
    attr_reader :explicit_keys

    # A copy with some values replaced or dropped, keeping which keys the
    # user set explicitly: the replacements count as explicit, the dropped
    # keys lose it (#296).
    def with(values, except: [])
      merged = to_h.except(*except).merge(values)
      Config.new(merged, root: root, explicit: (explicit_keys - except.map(&:to_s)) | values.keys.map(&:to_s))
    end

    # Whether the user set a key (config file or CLI flag) rather than
    # relying on the default. An explicitly requested report artifact is
    # completion evidence, so its write failure is a hard error (#296).
    def explicit?(key)
      @explicit_keys.include?(key.to_s)
    end

    def to_h
      @values.dup
    end

    # Ruby files to mutate, as absolute real paths.
    def included_files
      matched = self["include"].flat_map { |pattern| Dir.glob(pattern, base: root) }
      excluded = self["exclude"].flat_map { |pattern| Dir.glob(pattern, base: root) }
      (matched - excluded).select { |file| file.end_with?(".rb") }
                          .filter_map { |file| real_source_path(file) }
                          .uniq.sort
    end

    # A broken symlink matches Dir.glob but has no real path: dangling
    # (ENOENT), a loop (ELOOP) or through a regular file (ENOTDIR). It is
    # not mutation source, so it is skipped rather than crashing the run
    # (#503). A regular file that cannot be resolved still raises.
    def real_source_path(file)
      path = File.expand_path(Text.utf8_identity(file), root)
      File.realpath(path)
    rescue SystemCallError
      raise unless File.symlink?(path)
    end

    # Patterns that match no file. A pattern goes stale when files move;
    # an exclude that silently stops excluding is a hazard, so say so.
    def unmatched_patterns
      %w[include exclude].flat_map do |key|
        # The default exclude shields (#504) match nothing on a healthy
        # project - that is their job - so only a configured exclude can go
        # stale enough to warn about.
        next [] if key == "exclude" && !explicit?("exclude")

        self[key].select { |pattern| Dir.glob(pattern, base: root).empty? }.map { |pattern| "#{key}: #{pattern}" }
      end
    end

    def path(key)
      value = self[key]
      value && File.expand_path(value, root)
    end

    # Paths of saboteur's own output, relative to the root, that do not count as source changes.
    def output_paths
      prefix = File.join(File.realpath(root), "")
      OUTPUT_KEYS.filter_map { |key| path(key) }
                 .select { |file| file.start_with?(prefix) }
                 .map { |file| file.delete_prefix(prefix) }
    end

    # Tool-owned paths, relative to the root, that never count as
    # working-tree changes (#638): the run's output, plus an in-repo
    # BUNDLE_GEMFILE sidecar and its lock - the documented trial setup
    # should not read as a dirty tree. Path-exact, never a glob, so a
    # real untracked Gemfile.lock still counts.
    def ignored_tree_paths(gemfile: ENV.fetch("BUNDLE_GEMFILE", nil))
      prefix = File.join(File.realpath(root), "")
      sidecar = gemfile && File.expand_path(gemfile, prefix)
      begin
        sidecar &&= File.join(File.realpath(File.dirname(sidecar)), File.basename(sidecar))
      rescue SystemCallError
        # The sidecar's directory does not exist; keep the expanded spelling.
      end
      paths = output_paths
      if sidecar&.start_with?(prefix) && sidecar != File.join(prefix, "Gemfile")
        paths.concat([sidecar, DirtyTreeWarning.lockfile_for(sidecar)].map { |file| file.delete_prefix(prefix) })
      end
      paths
    end

    private

    # An explicit guess_tests = false (config file or --no-guess-tests) used
    # to keep the whole suite; inference is the default now, so the opt-out
    # is --all / c.test_selection = :all. guess_tests = true is the default
    # behavior spelled out, so it stays silent.
    def deprecations(values)
      return [] unless values["guess_tests"] == false

      ["guess_tests = false is deprecated: inferred specs are the default and it no longer restores the " \
       "whole suite; use --all or c.test_selection = :all to run every spec"]
    end

    def coerce!
      INTEGER_KEYS.each { |key| @values[key] = Integer(@values[key]) }
      FLOAT_KEYS.each { |key| @values[key] = Float(@values[key]) }
      LIST_KEYS.each { |key| @values[key] = Array(@values[key]).map(&:to_s) }
      NILABLE_FLOAT_KEYS.each { |key| @values[key] = Float(@values[key]) unless @values[key].nil? }
      STRING_KEYS.each { |key| @values[key] = @values[key].to_s }
    rescue ArgumentError, TypeError => e
      raise ConfigError, "invalid config value: #{e.message}"
    end

    def validate_partial_coverage!
      return if %w[off shadow use].include?(self["partial_coverage"])

      raise ConfigError, "partial_coverage must be one of: off, shadow, use"
    end

    def validate_coverage_settings!
      validate_partial_coverage!
      validate_coverage_recorder!
    end

    def validate_coverage_recorder!
      return if %w[coverage trace].include?(self["coverage_recorder"])

      raise ConfigError, "coverage_recorder must be one of: coverage, trace"
    end

    def validate_mutant_limit!
      raise ConfigError, "max_mutants_per_method must be > 0" unless self["max_mutants_per_method"].positive?
    end

    # The unchanged-suite checks: how many, and the whole run's clock (#55, #245).
    def validate_baseline!
      raise ConfigError, "seed must be >= 0" if self["seed"].negative?
      raise ConfigError, "baseline_passes must be >= 1" if self["baseline_passes"] < 1
      raise ConfigError, "coverage_parts must be >= 1" if self["coverage_parts"] < 1
      raise ConfigError, "max_duration must be > 0" if self["max_duration"] && !self["max_duration"].positive?
    end

    def validate_report_paths!
      json = path("json_report")
      if json && json == path("html_report")
        raise ConfigError, "json_report and html_report both point to #{json}; give each report its own path"
      end

      paths = %w[json_report html_report score_history].filter_map { |key| path(key) }
      return if paths.uniq.size == paths.size

      raise ConfigError, "json_report, html_report and score_history must have distinct paths"
    end

    def validate_modes!
      validate_palette!
      validate_fail_fast!
      validate_matrix!
      validate_resume!
      validate_test_selection!
      validate_gates!
      validate_score_gates!
    end

    # Per-path gates (#473): normalize each entry to string pattern /
    # float floor, and fail loud on a pattern no included file matches -
    # a gate that matches nothing would pass vacuously forever.
    def validate_score_gates!
      gates = self["score_gates"]
      return if gates.empty?

      normalized = gates.map { |gate| normalize_score_gate(gate) }
      prefix = File.join(File.realpath(root), "")
      relative = included_files.map { |file| file.delete_prefix(prefix) }
      flags = File::FNM_PATHNAME | File::FNM_EXTGLOB
      normalized.each do |gate|
        next if relative.any? { |file| File.fnmatch?(gate["pattern"], file, flags) }

        raise ConfigError, "score_gate #{gate['pattern']} matches no included file"
      end
      @values["score_gates"] = normalized
    end

    def normalize_score_gate(gate)
      pattern = gate["pattern"].to_s
      begin
        floor = Float(gate["min_score"])
      rescue ArgumentError, TypeError
        raise ConfigError, "score_gate min_score must be between 0 and 100, got #{gate['min_score'].inspect}"
      end
      unless floor.finite? && floor.between?(0, 100)
        raise ConfigError, "score_gate min_score must be between 0 and 100, got #{gate['min_score'].inspect}"
      end
      raise ConfigError, "score_gate pattern must not be empty" if pattern.empty?

      { "pattern" => pattern, "min_score" => floor }
    end

    def validate_gates!
      Gates::SETTINGS.each_key { |key| Gates.limit(self[key], key) }
    end

    def validate_fail_fast!
      return unless self["fail_fast"] && self["jobs"] > 1

      raise ConfigError, "fail_fast needs jobs 1: parallel workers have already started the other subjects"
    end

    # A reused verdict was computed by a run that stopped at the first
    # failing test, so it lists too few killers for a matrix.
    def validate_matrix!
      return unless self["matrix"] && self["incremental"]

      raise ConfigError, "matrix cannot be combined with incremental: reused verdicts list only the first killer"
    end

    # --resume DIR keeps verdicts in DIR for a later run (#471); it reuses
    # them the way --incremental does, so the same limits apply.
    def validate_resume!
      resume = self["resume"]
      return if resume.nil?
      raise ConfigError, "resume must be a non-blank directory path" unless resume.is_a?(String) && !resume.strip.empty?
      return unless self["matrix"] || !self["test_command"].to_s.empty?

      raise ConfigError, "resume cannot be combined with matrix or test_command: reused verdicts are not valid there"
    end

    def validate_threshold!
      threshold = self["threshold"]
      return if threshold.nil? || THRESHOLD_RANGE.cover?(threshold)

      raise ConfigError, "threshold must be between 0 and 100"
    end

    def validate_test_selection!
      return if %w[auto all].include?(self["test_selection"])

      raise ConfigError, "test_selection must be one of: auto, all"
    end

    # --test-command replaces the whole in-process machinery, on the
    # EFFECTIVE config: CLI flags and config-file entries alike (#305).
    # The command runs unsandboxed, so "strict" cannot be honored.
    def validate_test_command!
      command = self["test_command"]
      # nil alone means unset: false, arrays and numbers are all rejected,
      # never coerced and never sent to String methods (#305 QA).
      raise ConfigError, "test_command must be a string" unless command.nil? || command.is_a?(String)
      raise ConfigError, "test_command must not be blank" if command&.strip&.empty?

      return if command.to_s.empty?
      raise ConfigError, "test_command cannot be combined with tests" unless self["tests"].empty?
      raise ConfigError, "test_command cannot be combined with incremental" if self["incremental"]
      unless self["flaky_check"] == "off"
        raise ConfigError, "test_command cannot be combined with flaky_check: an external run has no " \
                           "in-process scheduler to rerun the decisive tests through"
      end
      return unless self["sandbox"] == "strict"

      raise ConfigError, 'test_command runs the command unsandboxed, so sandbox "strict" cannot be honored'
    end

    def validate_palette!
      Reporter::Palette.validate_overrides!(self["palette"])
    rescue ArgumentError => e
      raise ConfigError, e.message
    end

    def validate_reeval!
      raise ConfigError, "reeval must be one of: #{Execution::Reevaluator::STRATEGIES.join(', ')}" unless
        Execution::Reevaluator::STRATEGIES.include?(self["reeval"].to_s)
    end

    def validate!
      raise ConfigError, "jobs must be >= 1" if self["jobs"] < 1
      unless [true, false, "strict", "seatbelt"].include?(self["sandbox"])
        raise ConfigError, 'sandbox must be true, false, "strict", or "seatbelt"'
      end
      unless %w[off survivors decisive].include?(self["flaky_check"])
        raise ConfigError, "flaky_check must be one of: off, survivors, decisive"
      end

      validate_coverage_settings!
      validate_mutant_limit!
      validate_threshold!
      validate_modes!
      validate_baseline!
      raise ConfigError, "max_memory_mb must be > 0" unless self["max_memory_mb"].positive?
      raise ConfigError, "max_processes must be > 0" unless self["max_processes"].positive?
      raise ConfigError, "timeout_factor must be > 0" unless self["timeout_factor"].positive?
      raise ConfigError, "timeout_min must be > 0" unless self["timeout_min"].positive?

      validate_reeval!
      validate_operator_config!
      validate_test_command!
    end

    public

    def operator_policy
      MutationSource::OperatorRegistry.policy(self["operators"], self["exclude_operators"])
    end

    # Versioned policy travels with every identity, not with mutation digests.
    def selection_settings
      to_h.merge("operator_policy" => operator_policy)
    end

    private

    def validate_operator_config!
      effective = MutationSource::OperatorRegistry.select(self["operators"], self["exclude_operators"])
      if effective.empty?
        raise ConfigError,
              "operator selection is empty: enable at least one operator or clear exclusions"
      end

      self["arid"].each { |pattern| Regexp.new(pattern) }
    rescue RegexpError => e
      raise ConfigError, "invalid arid pattern: #{e.message}"
    end
  end
end

require_relative "config_file"
