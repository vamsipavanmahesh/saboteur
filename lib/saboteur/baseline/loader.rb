# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "json"

require_relative "acceptance"
require_relative "evidence"
require_relative "manifest"
require_relative "../text"

module Saboteur
  module Baseline
    # Loading an accepted baseline manifest, shared by the baseline workflow
    # and the `run --baseline` gate: size cap, strict parse, then manifest and
    # evidence validation. Returns [manifest, sha256 of the exact bytes], so a
    # caller can notice the file changing while the run executes.
    module Loader
      module_function

      def call(path)
        raise ConfigError, "baseline file too large" if File.size(path) > Acceptance::MAX_BYTES

        bytes = File.read(path)
        digest = Digest::SHA256.hexdigest(bytes)
        manifest = Manifest.new(JSON.parse(Text.utf8_strict(bytes)))
        Evidence.new(restored_evidence(manifest))
        [manifest, digest]
      rescue Errno::ENOENT
        raise ConfigError, "baseline file #{path} does not exist; " \
                           "create it with saboteur baseline propose --baseline #{path}"
      rescue SystemCallError, JSON::ParserError, ArgumentError => e
        raise ConfigError, "baseline file: #{e.message}"
      end

      # The evidence snapshot a manifest stands for: its metadata, candidates
      # and plan, with no generation events (nothing was generated).
      def restored_evidence(manifest)
        metadata = manifest.to_h.fetch("metadata")
        candidates = manifest.candidates.values
        issues = metadata.fetch("issues")
        metadata.slice("snapshot", "subjects", "complete", "issues").merge(
          "proposable" => metadata.fetch("proposable", metadata["complete"]),
          "blockers" => issues.reject { |issue| Completeness.soft_gap?(issue) },
          "gaps" => issues.select { |issue| Completeness.soft_gap?(issue) }
        ).merge(
          "compatibility" => manifest.compatibility, "candidates" => candidates,
          "planned" => candidates.map { |entry| entry.slice(*Evidence::PLAN_FIELDS) },
          "generation_events" => [], "omissions" => [], "discovery_failures" => [], "inline_suppressions" => []
        )
      end
    end
  end
end
