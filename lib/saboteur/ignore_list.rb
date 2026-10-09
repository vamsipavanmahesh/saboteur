# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "yaml"

module Saboteur
  # Survivors the team has accepted. YAML list of entries:
  #
  #   - subject: "Person#adult?"
  #     mutation: "1a2b3c4d5e6f7a8b"   # digest shown next to each survivor
  #     reason: "equivalent: age is always an integer"
  #
  # reason is mandatory; a file with a missing or blank reason does not load.
  class IgnoreList
    Entry = Data.define(:subject, :mutation, :reason)

    attr_reader :entries

    def self.load(path)
      return new([]) unless path && File.file?(path)

      data = YAML.safe_load_file(path) || []
      raise ConfigError, "#{path}: expected a list of entries" unless data.is_a?(Array)

      new(data.each_with_index.map { |raw, index| parse_entry(raw, path, index) })
    rescue Psych::SyntaxError => e
      raise ConfigError, "#{path}: #{e.message}"
    end

    def self.parse_entry(raw, path, index)
      raise ConfigError, "#{path}: entry #{index + 1} is not a mapping" unless raw.is_a?(Hash)

      values = %w[subject mutation reason].to_h { |key| [key, raw[key].to_s.strip] }
      missing = values.select { |_, value| value.empty? }.keys
      raise ConfigError, "#{path}: entry #{index + 1} is missing #{missing.join(', ')}" if missing.any?

      Entry.new(subject: values["subject"], mutation: values["mutation"], reason: values["reason"])
    end

    def initialize(entries)
      @entries = entries
      @index = entries.to_h { |entry| [[entry.subject, entry.mutation], entry] }
    end

    # Marks matching survivors as ignored. Returns warnings for stale entries:
    # entries whose subject was examined but whose mutation no longer exists.
    def apply(results)
      seen = {}
      results.each do |result|
        key = [result.subject.id, result.digest]
        entry = @index[key]
        next unless entry

        seen[key] = true
        result.ignored = entry.reason if result.survived?
      end
      examined = results.to_set { |result| result.subject.id }
      entries.select { |entry| examined.include?(entry.subject) && !seen[[entry.subject, entry.mutation]] }
             .map { |entry| "stale ignore entry #{entry.subject} #{entry.mutation}: no such mutation" }
    end
  end
end
