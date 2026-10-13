# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Entry point used by config/saboteur_ignore.rb.
  def self.ignore
    collector = IgnoreList.current_collector
    raise "Saboteur.ignore is only valid while config/saboteur_ignore.rb loads" unless collector

    yield collector
    collector
  end

  # Survivors the team has accepted. config/saboteur_ignore.rb declares them:
  #
  #   Saboteur.ignore do |i|
  #     i.mutation "1a2b3c4d5e6f7a8b",
  #                subject: "Person#adult?",
  #                reason: "equivalent: age is always an integer"
  #   end
  #
  # reason is mandatory; a file with a missing or blank reason does not load.
  class IgnoreList
    Entry = Data.define(:subject, :mutation, :reason)

    # Collects the entries a saboteur_ignore.rb file declares.
    class Collector
      attr_reader :entries

      def initialize
        @entries = []
      end

      def mutation(digest = nil, subject: nil, reason: nil)
        line = caller_locations(1, 1).first.lineno
        values = { "subject" => subject, "mutation" => digest, "reason" => reason }
        missing = values.select { |_, value| value.to_s.strip.empty? }.keys
        raise ConfigError, "#{line}: entry is missing #{missing.join(', ')}" if missing.any?

        @entries << Entry.new(
          subject: subject.to_s.strip,
          mutation: digest.to_s.strip,
          reason: reason.to_s.strip
        )
      end
    end

    attr_reader :entries

    # The collector is process-global on purpose: the ignore file calls the
    # top-level Saboteur.ignore, which must reach the load in progress.
    # Loads are therefore serialized - never load two ignore files at once.
    def self.load(path)
      return new([]) unless path && File.file?(path)

      @collector = Collector.new
      Kernel.load(path)
      new(@collector.entries)
    rescue ConfigError => e
      raise ConfigError, "#{path}:#{e.message}"
    rescue NoMethodError => e
      raise ConfigError, unknown_directive_message(path, e) if e.receiver.is_a?(Collector)

      # A typo'd call outside the collector: same treatment as a bare
      # constant, or the raw NoMethodError points at our internals.
      raise ConfigError, name_error_message(path, e)
    rescue SyntaxError, LoadError => e
      raise ConfigError, "#{path}: #{e.message.lines.first.to_s.chomp}"
    rescue NameError => e
      raise ConfigError, name_error_message(path, e)
    ensure
      @collector = nil
    end

    def self.unknown_directive_message(path, error)
      line = error.backtrace_locations.find { |loc| loc.path == path }&.lineno
      "#{path}:#{line}: unknown directive #{error.name.to_s.inspect} - " \
        'declare entries with mutation "<digest>", subject:, reason:'
    end

    def self.name_error_message(path, error)
      line = error.backtrace_locations&.find { |loc| loc.path == path }&.lineno
      "#{path}:#{line}: #{error.message.lines.first.to_s.chomp} " \
        "- this file loads before the app boots; use plain Ruby or ENV"
    end

    private_class_method :unknown_directive_message, :name_error_message

    # The Collector Saboteur.ignore hands to the file being loaded.
    def self.current_collector
      @collector
    end

    def initialize(entries)
      @entries = entries
      @index = entries.to_h { |entry| [[entry.subject, entry.mutation], entry] }
    end

    # True when this result is a survivor the list accepts.
    def accepts?(result)
      result.survived? && @index.key?([result.subject.id, result.digest])
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
