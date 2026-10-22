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
    # Triage states beyond plain ignoring (#155): accepted_equivalent and
    # wont_fix suppress the survivor's exit failure (it still counts in the
    # score), todo records the decision to fix and lets the survivor count.
    STATES = %w[accepted_equivalent wont_fix todo].freeze

    Entry = Data.define(:subject, :mutation, :reason, :state) do
      # Entries built without a state predate triage states: they accept.
      def initialize(subject:, mutation:, reason:, state: "accepted_equivalent") = super
    end

    # Collects the entries a saboteur_ignore.rb file declares.
    class Collector
      attr_reader :entries

      def initialize
        @entries = []
      end

      def mutation(digest = nil, subject: nil, reason: nil, state: nil)
        line = caller_locations(1, 1).first.lineno
        values = { "subject" => subject, "mutation" => digest, "reason" => reason }
        missing = values.select { |_, value| value.to_s.strip.empty? }.keys
        raise ConfigError, "#{line}: entry is missing #{missing.join(', ')}" if missing.any?

        state = state.to_s.strip
        state = "accepted_equivalent" if state.empty?
        unless STATES.include?(state)
          raise ConfigError, "#{line}: unknown state #{state.inspect} - use one of #{STATES.join(', ')}"
        end

        @entries << Entry.new(
          subject: subject.to_s.strip,
          mutation: digest.to_s.strip,
          reason: reason.to_s.strip,
          state: state
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

    # True when this result is a survivor the list accepts: a todo entry
    # records the triage but keeps the survivor counting as unignored.
    def accepts?(result)
      return false unless result.survived?

      entry = @index[[result.subject.id, result.digest]]
      !entry.nil? && entry.state != "todo"
    end

    # Marks matching survivors as ignored. Returns warnings for stale entries:
    # entries whose subject was examined but whose mutation no longer exists.
    # unscoped_digests (subject id => every digest generated before a diff
    # scope cut) keeps a scoped run from calling a scoped-out entry stale
    # (#284).
    def apply(results, subjects: nil, unscoped_digests: nil, full_run: false)
      seen = {}
      results.each do |result|
        key = [result.subject.id, result.digest]
        entry = @index[key]
        next unless entry

        seen[key] = true
        next unless result.survived?

        result.triage_state = entry.state
        result.triage_reason = entry.reason
        result.ignored = entry.reason if entry.state != "todo"
      end
      duplicate_warnings + stale_warnings(results, seen, unscoped_digests) +
        missing_subject_warnings(results, subjects, full_run: full_run)
    end

    private

    def stale_warnings(results, seen, unscoped_digests)
      examined = results.to_set { |result| result.subject.id }
      entries.select { |entry| examined.include?(entry.subject) && !seen[[entry.subject, entry.mutation]] }
             .reject { |entry| unscoped_digests&.fetch(entry.subject, nil)&.include?(entry.mutation) }
             .map { |entry| stale_message(entry) }
    end

    # Entries naming the same (subject, mutation) more than once: the index
    # keeps the last one, which is invisible otherwise (#1207).
    def duplicate_warnings
      entries.group_by { |entry| [entry.subject, entry.mutation] }
             .reject { |_, group| group.one? }
             .map { |(subject, mutation), _| "duplicate ignore entry #{subject} #{mutation}: the last entry wins" }
    end

    # A full run examines every in-scope subject, so an entry whose subject
    # never appears points at code that was renamed or removed - say so, but
    # only then: a scoped (--since/--subject) run cannot tell "renamed" from
    # "not in this diff" (#1206). The run's subject list is the source of
    # truth when given: an examined subject with no results (uncovered, or
    # nothing mutable left) is not missing.
    def missing_subject_warnings(results, subjects, full_run:)
      return [] unless full_run

      examined = (subjects || results).to_set { |item| item.respond_to?(:id) ? item.id : item.subject.id }
      entries.reject { |entry| examined.include?(entry.subject) }
             .map { |entry| missing_subject_message(entry) }
    end

    def missing_subject_message(entry)
      "stale ignore entry #{entry.subject} #{entry.mutation}: subject not found " \
        "(renamed, removed, or its file is excluded?) - remove the entry or fix the subject name"
    end

    def stale_message(entry)
      "stale ignore entry #{entry.subject} #{entry.mutation}: no such mutation " \
        "- remove the entry or refresh its digest (saboteur survivors --show)"
    end
  end
end
