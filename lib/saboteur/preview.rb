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
      @out.puts("Total: #{lists.sum(&:size)} mutants; #{@diagnostics.omissions.sum(&:count)} " \
                "dropped by max_mutants_per_method")
      estimate(subjects, lists)
      @diagnostics.warnings.each { |warning| @out.puts("warning: #{warning}") }
      nil
    end

    private

    def estimate(subjects, lists)
      path = File.join(@config.path("cache_dir"), "preview.json")
      receipt = JSON.parse(File.read(path)) if File.file?(path)
      fingerprint = Engine::RunFingerprint.new(config: @config).snapshot.digest
      map = Selection::CoverageMap.load(receipt["path"]) if receipt && receipt["fingerprint"] == fingerprint
      unless map
        @out.puts("no estimate: run once to build the coverage map")
        return
      end
      seconds = subjects.zip(lists).sum do |subject, list|
        runtime = map.recorded_runtime(map.tests_for(subject))
        return @out.puts("no estimate: cached test durations are incomplete") unless runtime

        runtime * list.size
      end
      @out.puts("Estimated covering-test work: #{seconds.round(2)} s (upper bound; excludes boot and forks)")
    rescue JSON::ParserError
      @out.puts("no estimate: run once to build the coverage map")
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
