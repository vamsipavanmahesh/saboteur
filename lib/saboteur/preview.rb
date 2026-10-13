# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "engine"

module Saboteur
  # Source-only planning. Never boots the host or executes its test suite.
  class Preview
    def initialize(config, out:, err:)
      @config = config
      @out = out
      @diagnostics = Engine::Diagnostics.new(err)
    end

    def call
      selection = Engine::SubjectSelection.new(@config, @diagnostics)
      subjects = selection.select(@config.included_files)
      scope = selection.changed_lines && Engine::DiffScope.new(selection.changed_lines)
      guard = MutationSource::HazardGuard.new(@config["hazard"]) unless @config["allow_hazardous"]
      candidates = Engine::Candidates.new(Engine::Candidates.build_sources(@config), @diagnostics, hazard_guard: guard)
      lists = subjects.map { |subject| planned(subject, candidates, scope) }
      incomplete = @diagnostics.discovery_failures.size
      @out.puts("Total: #{lists.sum(&:size)} mutants; #{@diagnostics.omissions.sum(&:count)} " \
                "dropped by max_mutants_per_method#{incomplete_note(incomplete)}")
      incomplete.zero? ? estimate(subjects, lists) : @out.puts("no estimate: source discovery was incomplete")
      @diagnostics.warnings.each { |warning| @out.puts("warning: #{warning}") }
      nil
    end

    private

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

    # Cached data is untrusted input: a duration must be a number that is not
    # negative (JSON cannot carry NaN or Infinity), and anything that fails
    # while reading it, such as a string or null, is no estimate. Source
    # generation has already finished, so this cannot hide its errors.
    def work_seconds(map, subjects, lists)
      return unless map.durations.values.all? { |seconds| seconds >= 0 }

      subjects.zip(lists).sum do |subject, list|
        # nil when a covering test has no recorded duration: the rescue below.
        map.recorded_runtime(map.tests_for(subject)) * list.size
      end
    rescue StandardError
      nil
    end

    # Any receipt that is not exactly a current, readable pointer to a
    # coverage map means "no estimate", never an exception.
    def cached_map
      path = File.join(@config.path("cache_dir"), "preview.json")
      receipt = JSON.parse(File.read(path))
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
