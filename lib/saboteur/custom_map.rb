# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Explicit source-file -> spec-file mapping from config/saboteur_custom_map.rb:
  #
  #   SABOTEUR_CUSTOM_MAP = {
  #     "app/services/tax_sync.rb" => ["spec/services/tax_sync_spec.rb"],
  #     "app/services/**/*.rb"     => ["spec/services/**/*_spec.rb"],
  #     %r{\Aapp/jobs/(.*)\.rb\z}  => ['spec/jobs/\1_spec.rb'],
  #     "app/generated/**/*.rb"    => [], # intentionally untested
  #   }.freeze
  #
  # The file loads before the app boots, so it must be plain Ruby.
  class CustomMap
    CONSTANT = :SABOTEUR_CUSTOM_MAP

    Entry = Data.define(:key, :specs)

    attr_reader :entries, :root

    def self.load(path, root: Dir.pwd)
      return new([], root: root) unless path && File.file?(path)

      Object.send(:remove_const, CONSTANT) if Object.const_defined?(CONSTANT)
      Kernel.load(path)
      unless Object.const_defined?(CONSTANT)
        raise ConfigError, "#{path}: expected it to define #{CONSTANT} = { ... }.freeze"
      end

      data = Object.const_get(CONSTANT)
      raise ConfigError, "#{path}: #{CONSTANT} must be a Hash, got #{data.class}" unless data.is_a?(Hash)

      new(data.map { |key, specs| validate_entry(path, root, key, specs) }, root: root)
    rescue SyntaxError, LoadError => e
      raise ConfigError, "#{path}: #{e.message.lines.first.to_s.chomp}"
    ensure
      Object.send(:remove_const, CONSTANT) if Object.const_defined?(CONSTANT)
    end

    def self.validate_entry(path, root, key, specs)
      unless key.is_a?(String) || key.is_a?(Regexp)
        raise ConfigError, "#{path}: key #{key.inspect} must be a String path, glob, or Regexp"
      end
      unless specs.is_a?(Array)
        raise ConfigError, "#{path}: #{key.inspect} maps to #{specs.inspect}; wrap spec paths in an array"
      end

      specs.each { |spec| validate_spec(path, root, key, spec) }
      Entry.new(key: key, specs: specs)
    end

    def self.validate_spec(path, root, key, spec)
      unless spec.is_a?(String)
        raise ConfigError, "#{path}: #{key.inspect} maps to #{spec.inspect}; spec paths must be Strings"
      end
      return if key.is_a?(Regexp) && spec.match?(/\\\d/) # backreference filled in at match time

      expanded = File.expand_path(spec, root)
      unless expanded.start_with?("#{root}/")
        raise ConfigError, "#{path}: #{key.inspect} maps to #{spec.inspect}, which is outside the project root"
      end
      return if Dir.glob(expanded).any?

      raise ConfigError, "#{path}: #{key.inspect} maps to #{spec.inspect}, which matches no file"
    end

    private_class_method :validate_entry, :validate_spec

    def initialize(entries, root: Dir.pwd)
      @entries = entries
      @root = root
    end

    def empty?
      @entries.empty?
    end

    # Spec paths for a source file, nil when no entry matches, :excluded when
    # the winning entry maps to an empty array (intentionally untested).
    def specs_for(file)
      exact = @entries.find { |entry| entry.key == file }
      return resolve(exact, nil) if exact

      glob = glob_entry(file)
      return resolve(glob, nil) if glob

      regexp_specs(file)
    end

    # String keys (exact or glob) that match nothing under the root.
    def stale_keys
      @entries.select { |entry| entry.key.is_a?(String) }
              .reject { |entry| Dir.glob(File.join(@root, entry.key)).any? }
              .map(&:key)
    end

    # Literal String keys written twice (Ruby silently keeps the last).
    def duplicate_keys(path)
      seen = Hash.new(0)
      File.readlines(path).each do |line|
        seen[::Regexp.last_match(1)] += 1 if line =~ /^\s*"(.+?)"\s*=>/
      end
      seen.select { |_, count| count > 1 }.keys
    end

    def self.glob?(pattern, file)
      File.fnmatch?(pattern, file, File::FNM_PATHNAME | File::FNM_EXTGLOB)
    end

    private

    def glob_entry(file)
      globs = @entries.select { |entry| entry.key.is_a?(String) && self.class.glob?(entry.key, file) }
      return nil if globs.empty?

      best = globs.group_by { |entry| specificity(entry.key) }.max_by { |score, _| score }.last
      if best.size > 1
        raise ConfigError,
              "custom map keys #{best.map { |e| e.key.inspect }.join(' and ')} both match #{file} " \
              "with equal specificity; make one more specific"
      end
      best.first
    end

    def regexp_specs(file)
      matches = @entries.filter_map do |entry|
        next unless entry.key.is_a?(Regexp)

        match = entry.key.match(file)
        [entry, match] if match
      end
      return nil if matches.empty?
      return :excluded if matches.all? { |entry, _| entry.specs.empty? }

      matches.flat_map { |entry, match| resolve(entry, match) }
    end

    def specificity(key)
      key.count("^*?[]{}\\")
    end

    def resolve(entry, match)
      return :excluded if entry.specs.empty?

      specs = entry.specs
      specs = specs.map { |spec| spec.gsub(/\\(\d+)/) { match[::Regexp.last_match(1).to_i].to_s } } if match
      specs
    end
  end
end
