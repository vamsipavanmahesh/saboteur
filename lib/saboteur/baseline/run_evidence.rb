# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "identity"
require_relative "completeness"
require_relative "../config"
require_relative "../engine/run_fingerprint"

module Saboteur
  module Baseline
    # Fresh, pre-boot file identity and exact planned/result reconciliation.
    # This does not attest external database, network or environment state.
    class RunEvidence
      SAFE_DROPS = %w[unchanged duplicate].freeze
      OUTPUT_SETTINGS = Config::OUTPUT_KEYS + Config::PRESENTATION_KEYS

      def initialize(config:, extra_files: [])
        @config = config
        @root = File.realpath(config.root)
        @fingerprint = Engine::RunFingerprint.new(config: config, extra_files: extra_files)
        @snapshot = @fingerprint.snapshot
      end

      def plan(subjects, lists)
        raise ConfigError, "baseline plan already recorded" if @planned
        raise ConfigError, "baseline candidate lists differ from subjects" unless subjects.size == lists.size

        @subjects = Engine::RunFingerprint.canonical_value(subjects.map do |subject|
          [relative(subject.file), subject.id]
        end)
        @planned = Engine::RunFingerprint.canonical_value(subjects.zip(lists).flat_map do |subject, candidates|
          candidates.map { |mutation, _| Identity.new(subject: subject, mutation: mutation, root: @root).entry }
        end)
      end

      def finish(results:, stable_suite:, skipped_subjects:, generation_events:, omissions:, discovery_failures: [],
                 inline_suppressions: [])
        raise ConfigError, "baseline plan missing" unless @planned

        observed = results.map { |result| outcome(result) }
        generation = generation_events.map { |event| event.to_h.transform_keys(&:to_s) }
        discovery = discovery_failures.map { |failure| failure.to_h.transform_keys(&:to_s) }
        errors = generation_issues(generation, results) + context_issues(observed) + discovery_issues(discovery)
        suppressions = suppression_scope(inline_suppressions)
        errors += suppression_issues(suppressions)
        @uncovered = uncovered_ids(results)
        completeness = assess(observed, stable_suite, skipped_subjects, omissions, errors)
        document = { "compatibility" => compatibility, "snapshot" => @snapshot.to_h, "subjects" => @subjects,
                     "candidates" => observed, "planned" => @planned,
                     "complete" => completeness.complete?, "proposable" => completeness.proposable?,
                     "issues" => completeness.issues, "blockers" => completeness.blockers,
                     "gaps" => completeness.gaps,
                     "generation_events" => generation, "omissions" => omissions.map(&:to_h),
                     "discovery_failures" => discovery, "inline_suppressions" => suppressions }
        Engine::RunFingerprint.canonical_value(document)
      end

      private

      def discovery_issues(entries)
        entries.map { |entry| "discovery:#{entry.fetch('reason')}:#{relative(entry.fetch('file'))}" }
      end

      def suppression_scope(entries)
        entries.map { |entry| entry.transform_keys(&:to_s).merge("file" => relative(entry.fetch(:file))) }
      end

      def suppression_issues(entries)
        entries.map { |entry| "inline_suppressed:#{entry.fetch('subject')}:#{entry.fetch('digest')}" }
      end

      def generation_issues(generation, results)
        errors = generation.reject { |event| SAFE_DROPS.include?(event.fetch("reason")) }.map do |event|
          [event.fetch("reason"), event.fetch("subject"), event["operator"]].compact.join(":")
        end
        errors + results.select(&:reused?).map { |result| "reused:#{result.subject.id}" }
      end

      def context_issues(observed)
        planned = @planned.to_h { |entry| [entry.fetch("id"), entry.fetch("context")] }
        observed.filter_map do |entry|
          id = entry.fetch("id")
          "changed_context:#{id}" if planned.key?(id) && planned.fetch(id) != entry.fetch("context")
        end
      end

      # Mutants skipped only because no test runs their line.
      def uncovered_ids(results)
        uncovered = results.select { |result| result.reason&.start_with?("no coverage") }
        uncovered.map do |result|
          Identity.new(subject: result.subject, mutation: result.mutation, root: @root).entry.fetch("id")
        end
      end

      def assess(observed, stable_suite, skipped_subjects, omissions, errors)
        skipped = skipped_subjects.map { |subject, reason| "#{subject.id}:#{reason}" }
        Completeness.new(planned: @planned.map { |entry| entry.fetch("id") }, results: observed,
                         subjects: @subjects, stable_suite: stable_suite,
                         stable_inputs: @fingerprint.verify(@snapshot).unchanged, skipped_subjects: skipped,
                         omitted: omissions.map { |entry| "#{entry.subject}:#{entry.count}" },
                         generation_issues: errors, uncovered: @uncovered)
      end

      def compatibility
        { "generator" => { "saboteur" => VERSION, "sources" => @config["sources"],
                           "plugins" => @snapshot.inventory.select do |entry|
                             entry.kind == "source_plugin"
                           end.map(&:to_h) },
          "runtime" => Engine::RunFingerprint.runtime_identity,
          "config" => @config.selection_settings.except(*OUTPUT_SETTINGS),
          "scope" => { "include" => @config["include"], "exclude" => @config["exclude"],
                       "subjects" => @config["subjects"] } }
      end

      def outcome(result)
        Identity.new(subject: result.subject, mutation: result.mutation, root: @root).entry.merge(
          "status" => result.status.to_s, "kill_cause" => result.kill_cause
        )
      end

      def relative(file)
        path = Identity.canonical_path(file)
        raise ConfigError, "baseline subject outside project root" unless path.start_with?("#{@root}/")

        path.delete_prefix("#{@root}/")
      end
    end
  end
end
