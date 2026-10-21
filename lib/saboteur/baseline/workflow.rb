# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "acceptance"
require_relative "comparison"
require_relative "identity"
require_relative "loader"
require_relative "../engine"
require_relative "../text"

module Saboteur
  module Baseline
    # Opt-in orchestration: every check/proposal runs fresh; acceptance only
    # edits reasons after verifying private execution evidence and current inputs.
    class Workflow
      def initialize(config:, err: $stderr)
        @config = config
        @err = err
        @root = File.realpath(config.root)
        raise ConfigError, "baseline requires fresh whole or subject scope" if config["since"] || config["incremental"]
        raise ConfigError, "baseline cannot use a score threshold" if config["threshold"]
      end

      def check(path:, epsilon: nil)
        baseline = load_manifest(path)
        report = Engine.new(@config, err: @err, capture_evidence: true, evidence_files: [path]).call
        unless Digest::SHA256.file(path).hexdigest == @baseline_digest
          raise ConfigError,
                "baseline changed during check"
        end

        current = report.run_evidence
        Evidence.new(current) if current["complete"] == true
        # An incomplete producer report is useful for diagnosis, never acceptance.
        comparison = Comparison.new(baseline: { "compatibility" => baseline.compatibility,
                                                "accepted" => baseline.accepted.values,
                                                "candidates" => baseline.candidates.values },
                                    current: current, epsilon: epsilon)
        payload = { "state" => comparison.state, "exit_code" => comparison.exit_code,
                    "categories" => comparison.categories, "issues" => comparison.issues }
        payload["score"] = comparison.score if comparison.score
        payload
      end

      # Blockers carry only a digest and a status. Name the subject, operator
      # and the engine's recorded reason, and say how to unblock the proposal.
      def refuse_proposal(evidence, report)
        blockers = evidence.fetch("blockers")
        by_id = report.results.to_h do |result|
          [Identity.new(subject: result.subject, mutation: result.mutation, root: @root).entry.fetch("id"), result]
        end
        blockers.each { |issue| @err.puts("saboteur: baseline proposal blocker: #{describe_blocker(issue, by_id)}") }
        if blockers.any? { |issue| issue.start_with?("unexecuted:") }
          @err.puts("saboteur: cover the skipped code with specs or narrow include, then propose again")
        end
        raise Error, "baseline proposal needs a proposable run"
      end

      def describe_blocker(issue, by_id)
        match = /\Aunexecuted:([0-9a-f]{64}):(\w+)\z/.match(issue)
        result = match && by_id[match[1]]
        return issue unless result

        detail = "#{result.subject.id} #{result.mutation.operator}"
        detail += " - #{result.reason}" if result.reason
        "#{issue} (#{detail})"
      end

      def propose(proposal:, destination:, previous: nil)
        guard_artifacts(proposal, destination)
        preflight_outputs(proposal, destination, previous)
        report = Engine.new(@config, err: @err, capture_evidence: true).call
        evidence = report.run_evidence
        refuse_proposal(evidence, report) unless evidence["proposable"] == true

        captured = Evidence.new(evidence)
        store(captured.document.fetch("snapshot")).propose(document: captured.manifest,
                                                           evidence: captured.document, proposal: proposal,
                                                           destination: destination, previous: previous)
        payload = { "state" => "proposal", "proposal" => File.expand_path(proposal),
                    "destination" => File.expand_path(destination),
                    "survivors" => captured.manifest.fetch("accepted").size,
                    "candidates" => captured.manifest.fetch("candidates").size }
        gaps = evidence.fetch("gaps")
        payload["gaps"] = gaps unless gaps.empty?
        payload
      end

      def accept(proposal:, destination:, previous: nil)
        guard_artifacts(proposal, destination)
        # The store reads and binds the private record; verifier uses its recorded snapshot.
        accepted = store(nil).accept(proposal: proposal, destination: destination, previous: previous)
        { "state" => "accepted", "destination" => accepted }
      end

      private

      def load_manifest(path)
        manifest, @baseline_digest = Loader.call(path)
        manifest
      end

      def store(snapshot)
        captured = snapshot && Engine::RunFingerprint.restore_snapshot(snapshot)
        protected = input_paths(captured || Engine::RunFingerprint.new(config: @config).snapshot)
        verifier = lambda do |metadata|
          saved = Engine::RunFingerprint.restore_snapshot(metadata.fetch("snapshot"))
          extras = saved.inventory.select { |entry| entry.kind == "extra" }.map do |entry|
            { path: input_path(entry.path), required: entry.required }
          end
          raise_unless_unchanged(Engine::RunFingerprint.new(config: @config, extra_files: extras).verify(saved))
        end
        Acceptance.new(directory: File.join(Identity.canonical_path(@config.path("cache_dir")), "baseline-evidence"),
                       protected_paths: protected, verify: verifier, require_evidence: true)
      end

      def raise_unless_unchanged(result)
        return true if result.unchanged

        detail = result.changes.map { |change| "#{change.path} #{change.reason}" }.join(", ")
        detail = "verification incomplete" if detail.empty?
        raise ConfigError, "baseline inputs changed or unverified: #{detail}"
      end

      def input_paths(snapshot)
        snapshot.inventory.map { |entry| input_path(entry.path) }
      end

      def input_path(path)
        path.start_with?("external:") ? path.delete_prefix("external:") : File.join(@root, path)
      end

      # Cheap pre-checks before the full run; Acceptance re-verifies exclusively after it.
      def preflight_outputs(proposal, destination, previous)
        raise ConfigError, "baseline output exists: #{Identity.canonical_path(proposal)}" if File.exist?(proposal)

        # Mirrors Acceptance#verify_previous so a doomed proposal fails before the run.
        if previous.nil?
          raise ConfigError, "baseline destination exists" if File.exist?(destination)
        elsif !File.file?(destination) || Digest::SHA256.file(destination).hexdigest != previous
          raise ConfigError, "baseline previous destination changed"
        end
      end

      def guard_artifacts(*paths)
        paths.each do |path|
          expanded = Identity.canonical_path(path)
          next unless expanded.end_with?(".rb") || Engine::DataInputs.match?(@root, expanded,
                                                                             extra: @config["fingerprint_extra"]) ||
                      Engine::RunFingerprint::MANIFESTS.any? { |name| expanded == File.join(@root, name) }

          raise ConfigError, "baseline artifact overlaps project input: #{path}"
        end
      end
    end
  end
end
