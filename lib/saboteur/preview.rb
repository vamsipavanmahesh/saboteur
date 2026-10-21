# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require_relative "engine"
require_relative "text"
require_relative "version"

module Saboteur
  # Source-only planning. Never boots the host or executes its test suite.
  class Preview
    # Version of the --format json inventory (#469). Consumers ignore fields
    # they do not know; only a breaking change raises this number.
    SCHEMA_VERSION = 1

    def initialize(config, out:, err:, format: "text")
      @config = config
      @out = out
      @diagnostics = Engine::Diagnostics.new(err)
      @json = format == "json"
      @inventory = []
      @skipped = []
    end

    def call
      announce_operators
      selection = Engine::SubjectSelection.new(@config, @diagnostics)
      subjects = selection.select(@config.included_files)
      scope = selection.behavior_lines && Engine::DiffScope.new(selection.behavior_lines)
      guard = MutationSource::HazardGuard.new(@config["hazard"]) unless @config["allow_hazardous"]
      candidates = Engine::Candidates.new(Engine::Candidates.build_sources(@config), @diagnostics, hazard_guard: guard)
      lists = shard_lists(subjects, subjects.map { |subject| planned(subject, candidates, scope) })
      inline_suppressions
      incomplete = @diagnostics.discovery_failures.size
      return print_inventory(subjects, lists, incomplete) if @json

      print_totals(lists, incomplete)
      incomplete.zero? ? estimate(subjects, lists) : @out.puts("no estimate: source discovery was incomplete")
      print_warnings
      nil
    end

    private

    def shard_lists(subjects, lists)
      return lists unless @config["shard"]

      @shard = Engine::Shard.parse(@config["shard"])
      @shard.select(subjects, lists)
    end

    def print_totals(lists, incomplete)
      @out.puts(@shard.line) if @shard
      @out.puts("Total: #{lists.sum(&:size)} mutants; #{@diagnostics.omissions.sum(&:count)} " \
                "dropped by max_mutants_per_method#{incomplete_note(incomplete)}")
    end

    def print_warnings
      @diagnostics.warnings.each { |warning| @out.puts("warning: #{warning}") }
    end

    # The default set is what --list-operators prints, so a preview leads
    # with it only when the selection was changed or --verbose asks (#1178).
    def announce_operators
      return if @json
      return unless @config["verbose"] || @config["operators"].any? || @config["exclude_operators"].any?

      @out.puts("Operators: #{@config.operator_policy['effective'].join(', ')}")
    end

    # Candidate filtering precedes diff restriction and the per-method cap.
    # Name that scope rather than implying these rows were executed or scored.
    def inline_suppressions
      entries = @diagnostics.inline_suppressions
      return if entries.empty? || @json

      @out.puts("Inline suppressions: #{entries.size} candidates in selected methods " \
                "(before diff restriction and per-method cap; outside the planned total)")
      entries.each do |entry|
        @out.puts("  #{relative_path(entry[:file])}:#{entry[:line]} #{entry[:subject]} #{entry[:operator]} " \
                  "#{entry[:digest]}: #{entry[:reason]}")
      end
    end

    def incomplete_note(count)
      return "" if count.zero?

      " - INCOMPLETE: #{count} file(s) could not be parsed, so this total is not authoritative"
    end

    def estimate(subjects, lists)
      # External-command runs are serial and never build a coverage map, so
      # "run once" can never fix the estimate (#590): say what would.
      if @config["test_command"]
        return @out.puts("no estimate: --test-command runs never build a coverage map; " \
                         "estimates need the in-process rspec mode")
      end

      map = cached_map
      return @out.puts("no estimate: run once to build the coverage map") unless map

      seconds = work_seconds(map, subjects, lists)
      return @out.puts("no estimate: cached test durations are incomplete") unless seconds

      @out.puts("Estimated baseline covering-test work: #{seconds.round(2)} s (cached original-test durations " \
                "times planned mutants; not a bound on mutant runtime; excludes boot and forks)")
    end

    # Cached data is untrusted input: every duration must be a non-negative
    # number, the total must stay finite (JSON text such as 1e999 parses to
    # Infinity), and anything that fails while reading it, such as a string or
    # null, is no estimate. Source generation has already finished, so this
    # cannot hide its errors.
    def work_seconds(map, subjects, lists)
      return unless map.durations.values.all? { |seconds| seconds >= 0 }

      total = subjects.zip(lists).sum do |subject, list|
        # nil when a covering test has no recorded duration: the rescue below.
        map.recorded_runtime(map.tests_for(subject)) * list.size
      end
      total if total.finite?
    rescue StandardError
      nil
    end

    # Any receipt that is not exactly a current, readable pointer to a
    # coverage map means "no estimate", never an exception.
    def cached_map
      path = File.join(@config.path("cache_dir"), "preview.json")
      receipt = JSON.parse(Text.utf8_strict(File.read(path)))
      return unless receipt["fingerprint"] == Engine::RunFingerprint.new(config: @config).snapshot.digest

      Selection::CoverageMap.load(receipt["path"])
    rescue StandardError
      # An unreadable receipt or a map of the wrong shape (IndexError, TypeError, ...) is no estimate.
      nil
    end

    def planned(subject, candidates, scope)
      if subject.skip_reason
        @diagnostics.warn("#{subject.id} (#{subject.location(@config.root)}): skipped (#{subject.skip_reason}); " \
                          "excluded from the planned total")
        return []
      end

      list = candidates.for(subject)
      list = scope.restrict(subject, list) if scope
      limit = @config["max_mutants_per_method"]
      if list.size > limit
        @diagnostics.record_omission(subject, count: list.size - limit, limit: limit)
        list.drop(limit).each { |(mutation, _)| record_skip(subject, mutation, "max_mutants_per_method") } if @json
      end
      list = list.first(limit)
      if @json
        list.each { |(mutation, _)| @inventory << mutant_entry(subject, mutation) }
      else
        @out.puts("#{relative_path(subject.file)}:#{subject.start_line} #{subject.id}  #{list.size} mutants")
      end
      list
    end

    # The machine-readable inventory (#469): every planned mutant named by
    # the stable digest a run or --id replay computes, plus the candidates
    # that were planned but not runnable, each with its skip reason.
    def print_inventory(subjects, lists, incomplete)
      @out.puts(JSON.pretty_generate(
                  schema_version: SCHEMA_VERSION,
                  saboteur_version: VERSION,
                  mode: "dry-run",
                  operators: @config.operator_policy["effective"],
                  test_selection: @config["test_selection"],
                  tests: @config["tests"],
                  subjects: subjects.zip(lists).map { |subject, list| subject_entry(subject, list) },
                  mutants: @inventory,
                  skipped: @skipped + suppression_entries,
                  totals: {
                    mutants: lists.sum(&:size),
                    dropped_by_max_mutants_per_method: @diagnostics.omissions.sum(&:count),
                    incomplete_files: incomplete
                  },
                  estimated_seconds: incomplete.zero? ? estimated_seconds(subjects, lists) : nil,
                  warnings: @diagnostics.warnings
                ))
      nil
    end

    def estimated_seconds(subjects, lists)
      map = cached_map
      seconds = map && work_seconds(map, subjects, lists)
      seconds&.round(2)
    end

    def subject_entry(subject, list)
      { id: subject.id, file: relative_path(subject.file), start_line: subject.start_line,
        end_line: subject.end_line, mutants: list.size }
    end

    # Byte offsets index the file as read from disk, like the Stryker
    # report; original and replacement text make each edit self-contained.
    def mutant_entry(subject, mutation)
      {
        digest: mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source),
        subject: subject.id,
        operator: mutation.operator.to_s,
        file: relative_path(subject.file),
        line: subject.line_of(mutation.edits.first.start_byte),
        edits: mutation.edits.map do |edit|
          { start_byte: edit.start_byte, end_byte: edit.end_byte,
            original: source_span(subject, edit), replacement: edit.replacement }
        end
      }
    end

    def record_skip(subject, mutation, reason)
      @skipped << mutant_entry(subject, mutation).merge(reason: reason)
    end

    # Inline-suppressed and hazard-refused candidates with their reasons,
    # recorded during candidate filtering, before diff restriction and the
    # per-method cap (the same scope the text audit names).
    def suppression_entries
      inline = @diagnostics.inline_suppressions.map do |entry|
        { digest: entry[:digest], subject: entry[:subject], operator: entry[:operator].to_s,
          file: relative_path(entry[:file]), line: entry[:line], reason: "inline_suppression: #{entry[:reason]}" }
      end
      hazards = @diagnostics.generation_events.select { |event| event.source == "hazard_guard" }.map do |event|
        { subject: event.subject, operator: event.operator.to_s, file: relative_path(event.file),
          reason: "hazardous" }
      end
      inline + hazards
    end

    def relative_path(file)
      file.delete_prefix("#{@config.root}/")
    end

    def source_span(subject, edit)
      subject.file_source.byteslice(edit.start_byte, edit.end_byte - edit.start_byte).to_s
             .force_encoding(Encoding::UTF_8)
    end
  end
end
