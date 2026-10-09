# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "yaml"
require_relative "mutation_source/builtin"

module Saboteur
  # Settings from .saboteur.yml, overridden by CLI flags.
  class Config
    FILE = ".saboteur.yml"

    DEFAULTS = {
      "integration" => "rspec",
      "require" => [],
      "include" => ["lib/**/*.rb"],
      "exclude" => [],
      "arid" => MutationSource::Builtin::DEFAULT_ARID,
      "timeout_factor" => 3.0,
      "timeout_min" => 5.0,
      "baseline_timeout" => 300.0,
      "coverage_timeout" => 3600.0,
      "max_memory_mb" => 2048,
      "max_processes" => 64,
      "jobs" => 1,
      "ignore_file" => ".saboteur-ignore.yml",
      "sources" => ["builtin"],
      "hooks" => [],
      "rails" => false,
      "reeval" => "nesting",
      "cache_dir" => ".saboteur",
      "json_report" => ".saboteur/report.json",
      "rspec_args" => [],
      "subjects" => [],
      "since" => nil,
      "cache" => true,
      "incremental" => false
    }.freeze

    INTEGER_KEYS = %w[jobs max_memory_mb max_processes].freeze
    FLOAT_KEYS = %w[timeout_factor timeout_min baseline_timeout coverage_timeout].freeze
    LIST_KEYS = %w[require include exclude arid sources hooks rspec_args subjects].freeze

    attr_reader :root

    def self.load(root: Dir.pwd, path: nil, overrides: {})
      path ||= File.join(root, FILE)
      from_file = File.file?(path) ? parse(path) : {}
      new(from_file.merge(stringify(overrides)), root: root)
    end

    def self.parse(path)
      data = YAML.safe_load_file(path) || {}
      raise ConfigError, "#{path}: expected a mapping at the top level" unless data.is_a?(Hash)

      data
    rescue Psych::SyntaxError => e
      raise ConfigError, "#{path}: #{e.message}"
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
                          .map { |file| File.realpath(File.join(root, file)) }.uniq.sort
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

    private

    def coerce!
      INTEGER_KEYS.each { |key| @values[key] = Integer(@values[key]) }
      FLOAT_KEYS.each { |key| @values[key] = Float(@values[key]) }
      LIST_KEYS.each { |key| @values[key] = Array(@values[key]).map(&:to_s) }
    rescue ArgumentError, TypeError => e
      raise ConfigError, "invalid config value: #{e.message}"
    end

    def validate!
      raise ConfigError, "jobs must be >= 1" if self["jobs"] < 1
      raise ConfigError, "max_memory_mb must be > 0" unless self["max_memory_mb"].positive?
      raise ConfigError, "max_processes must be > 0" unless self["max_processes"].positive?
      raise ConfigError, "timeout_factor must be > 0" unless self["timeout_factor"].positive?
      raise ConfigError, "timeout_min must be > 0" unless self["timeout_min"].positive?
      raise ConfigError, "reeval must be one of: #{Execution::Reevaluator::STRATEGIES.join(', ')}" unless
        Execution::Reevaluator::STRATEGIES.include?(self["reeval"].to_s)

      self["arid"].each { |pattern| Regexp.new(pattern) }
    rescue RegexpError => e
      raise ConfigError, "invalid arid pattern: #{e.message}"
    end
  end
end
