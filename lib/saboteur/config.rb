# SPDX-License-Identifier: MIT
# frozen_string_literal: true

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

    DEFAULTS = {
      "integration" => "rspec",
      "require" => [],
      "include" => ["lib/**/*.rb"],
      "exclude" => [],
      "arid" => MutationSource::Builtin::DEFAULT_ARID,
      "hazard" => MutationSource::HazardGuard::DEFAULT_HAZARD,
      "allow_hazardous" => false,
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
      "hooks" => [],
      "rails" => false,
      "reeval" => "nesting",
      "cache_dir" => ".saboteur",
      "json_report" => ".saboteur/report.json",
      "html_report" => ".saboteur/report.html",
      "rspec_args" => [],
      "subjects" => [],
      "since" => nil,
      "cache" => true,
      "incremental" => false,
      "allow_focus" => false,
      "fail_fast" => false,
      "matrix" => false,
      "seed" => 1,
      "tests" => [],
      "fingerprint_extra" => [],
      "threshold" => nil
    }.freeze

    INTEGER_KEYS = %w[jobs max_memory_mb max_processes max_mutants_per_method seed].freeze
    FLOAT_KEYS = %w[timeout_factor timeout_min baseline_timeout coverage_timeout].freeze
    THRESHOLD_RANGE = (0.0..100.0)

    LIST_KEYS = %w[require include exclude arid hazard sources hooks rspec_args subjects tests
                   fingerprint_extra operators].freeze

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
      new(from_file.merge(stringify(overrides)), root: root)
    end

    def self.stringify(hash)
      hash.to_h { |key, value| [key.to_s, value] }.compact
    end

    def initialize(values = {}, root: Dir.pwd)
      @root = File.expand_path(root)
      unknown = values.keys - DEFAULTS.keys
      raise ConfigError, "unknown config key(s): #{unknown.join(', ')}" if unknown.any?

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

    def to_h
      @values.dup
    end

    # Ruby files to mutate, as absolute real paths.
    def included_files
      matched = self["include"].flat_map { |pattern| Dir.glob(pattern, base: root) }
      excluded = self["exclude"].flat_map { |pattern| Dir.glob(pattern, base: root) }
      (matched - excluded).select { |file| file.end_with?(".rb") }
                          .map { |file| File.realpath(File.expand_path(file, root)) }.uniq.sort
    end

    # Patterns that match no file. A pattern goes stale when files move;
    # an exclude that silently stops excluding is a hazard, so say so.
    def unmatched_patterns
      %w[include exclude].flat_map do |key|
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
      %w[cache_dir json_report html_report].filter_map { |key| path(key) }
                                           .map { |file| File.expand_path(file) }
                                           .select { |file| file.start_with?(prefix) }
                                           .map { |file| file.delete_prefix(prefix) }
    end

    private

    def coerce!
      INTEGER_KEYS.each { |key| @values[key] = Integer(@values[key]) }
      FLOAT_KEYS.each { |key| @values[key] = Float(@values[key]) }
      LIST_KEYS.each { |key| @values[key] = Array(@values[key]).map(&:to_s) }
      @values["threshold"] = Float(@values["threshold"]) unless @values["threshold"].nil?
    rescue ArgumentError, TypeError => e
      raise ConfigError, "invalid config value: #{e.message}"
    end

    def validate_mutant_limit!
      raise ConfigError, "max_mutants_per_method must be > 0" unless self["max_mutants_per_method"].positive?
    end

    def validate_report_paths!
      json = path("json_report")
      return unless json && json == path("html_report")

      raise ConfigError, "json_report and html_report both point to #{json}; give each report its own path"
    end

    def validate_modes!
      validate_fail_fast!
      validate_matrix!
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

    def validate_threshold!
      threshold = self["threshold"]
      return if threshold.nil? || THRESHOLD_RANGE.cover?(threshold)

      raise ConfigError, "threshold must be between 0 and 100"
    end

    def validate_reeval!
      raise ConfigError, "reeval must be one of: #{Execution::Reevaluator::STRATEGIES.join(', ')}" unless
        Execution::Reevaluator::STRATEGIES.include?(self["reeval"].to_s)
    end

    def validate!
      raise ConfigError, "jobs must be >= 1" if self["jobs"] < 1

      validate_mutant_limit!
      validate_threshold!
      validate_modes!
      raise ConfigError, "seed must be >= 0" if self["seed"].negative?
      raise ConfigError, "max_memory_mb must be > 0" unless self["max_memory_mb"].positive?
      raise ConfigError, "max_processes must be > 0" unless self["max_processes"].positive?
      raise ConfigError, "timeout_factor must be > 0" unless self["timeout_factor"].positive?
      raise ConfigError, "timeout_min must be > 0" unless self["timeout_min"].positive?

      validate_reeval!
      MutationSource::OperatorRegistry.resolve(self["operators"])

      self["arid"].each { |pattern| Regexp.new(pattern) }
    rescue RegexpError => e
      raise ConfigError, "invalid arid pattern: #{e.message}"
    end
  end
end

require_relative "config_file"
