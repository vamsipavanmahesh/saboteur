# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "engine"
require_relative "text"

module Saboteur
  # Source-only planning. Never boots the host or executes its test suite.
  class Preview
    def initialize(config, out:, err:)
      @config = config
      @out = out
      @diagnostics = Engine::Diagnostics.new(err)
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

    def announce_operators
      @out.puts("Operators: #{@config.operator_policy['effective'].join(', ')}")
    end

    # Candidate filtering precedes diff restriction and the per-method cap.
    # Name that scope rather than implying these rows were executed or scored.
    def inline_suppressions
      entries = @diagnostics.inline_suppressions
      return if entries.empty?

      @out.puts("Inline suppressions: #{entries.size} candidates in selected methods " \
                "(before diff restriction and per-method cap; outside the planned total)")
      entries.each do |entry|
        path = entry[:file].delete_prefix("#{@config.root}/")
        @out.puts("  #{path}:#{entry[:line]} #{entry[:subject]} #{entry[:operator]} " \
                  "#{entry[:digest]}: #{entry[:reason]}")
      end
    end

    def incomplete_note(count)
      return "" if count.zero?

      " - INCOMPLETE: #{count} file(s) could not be parsed, so this total is not authoritative"
    end

    def estimate(subjects, lists)
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
      list = candidates.for(subject)
      list = scope.restrict(subject, list) if scope
      limit = @config["max_mutants_per_method"]
      @diagnostics.record_omission(subject, count: list.size - limit, limit: limit) if list.size > limit
      list = list.first(limit)
      path = subject.file.delete_prefix("#{@config.root}/")
      @out.puts("#{path}:#{subject.start_line} #{subject.id}  #{list.size} mutants")
      list
    end
  end
end
