# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "manifest"
require_relative "run_evidence"
require_relative "../engine/run_fingerprint"

module Saboteur
  module Baseline
    # Validates the producer document before it can enter the acceptance path.
    # A claimed complete flag alone is never evidence of complete execution.
    class Evidence
      FIELDS = %w[compatibility snapshot subjects candidates planned complete proposable issues blockers gaps
                  generation_events omissions discovery_failures inline_suppressions].freeze
      COMPATIBILITY = %w[generator runtime config scope].freeze
      PLAN_FIELDS = %w[id identity context].freeze

      attr_reader :document

      def initialize(document)
        @document = Engine::RunFingerprint.canonical_value(document)
        fields!(@document, FIELDS)
        fields!(@document.fetch("compatibility"), COMPATIBILITY)
        @snapshot = Engine::RunFingerprint.restore_snapshot(@document.fetch("snapshot"))
        raise ConfigError, "baseline incomplete fingerprint" unless @snapshot.complete

        validate_compatibility
        validate_generation
        validate_plan
        # Manifest owns exact candidate, identity, subject and acceptance shapes.
        Manifest.new(manifest(reasons: "validation"))
        blockers = @document.fetch("blockers")
        gaps = @document.fetch("gaps")
        unless @document.fetch("proposable") == blockers.empty? &&
               (blockers + gaps).sort == @document.fetch("issues")
          raise ConfigError, "baseline evidence: completeness tiers disagree"
        end
      rescue ArgumentError, KeyError, TypeError, NoMethodError => e
        raise ConfigError, "baseline evidence: #{e.message}"
      end

      def manifest(reasons: "")
        metadata = document.fetch("compatibility").merge(document.slice("snapshot", "subjects", "complete",
                                                                        "proposable", "issues"))
        accepted = document.fetch("candidates").select { |entry| entry.fetch("status") == "survived" }.map do |entry|
          entry.slice("id", "context").merge("reason" => reasons)
        end
        { "format" => Manifest::FORMAT, "identity_version" => Identity::VERSION,
          "metadata" => metadata, "candidates" => document.fetch("candidates"), "accepted" => accepted }
      end

      private

      def array!(value, name)
        raise ConfigError, "baseline #{name}" unless value.is_a?(Array)
      end

      def fields!(value, fields)
        raise ConfigError, "baseline evidence fields" unless value.keys.sort == fields.sort
      end

      def validate_compatibility
        compatibility = document.fetch("compatibility")
        config = compatibility.fetch("config")
        runtime = compatibility.fetch("runtime")
        validate_operator_policy(config)
        fields!(runtime, %w[engine version platform patchlevel saboteur])
        raise ConfigError, "baseline nonfresh config" if config["since"] || config["incremental"]

        scope = config.slice("include", "exclude", "subjects")
        raise ConfigError, "baseline scope mismatch" unless compatibility.fetch("scope") == scope

        valid = digest(config) == @snapshot.settings_digest && digest(runtime) == @snapshot.runtime_digest
        raise ConfigError, "baseline snapshot settings mismatch" unless valid

        validate_generator(compatibility.fetch("generator"), config, runtime)
      end

      def validate_operator_policy(config)
        unless config["operator_policy"] && config["operator_policy"]["version"] == MutationSource::OperatorRegistry::POLICY_VERSION
          raise ConfigError, "baseline operator policy is incompatible; re-propose with baseline propose"
        end

        fields!(config, Config::DEFAULTS.keys - RunEvidence::OUTPUT_SETTINGS + ["operator_policy"])
        expected = Config.new(config.except("operator_policy")).operator_policy
        raise ConfigError, "baseline operator policy mismatch" unless expected == config["operator_policy"]
      end

      def validate_generator(generator, config, runtime)
        fields!(generator, %w[saboteur sources plugins])
        plugins = document.fetch("snapshot").fetch("inventory").select { |entry| entry["kind"] == "source_plugin" }
        raise ConfigError, "baseline generator mismatch" unless
          generator["saboteur"] == runtime["saboteur"] && generator["sources"] == config["sources"] &&
          generator["plugins"] == plugins
      end

      def digest(value)
        Digest::SHA256.hexdigest(JSON.generate(Engine::RunFingerprint.canonical_value(value)))
      end

      def validate_generation
        clear = document.values_at("omissions", "discovery_failures", "inline_suppressions").all? do |entries|
          entries == []
        end
        raise ConfigError, "baseline omitted or undiscovered work (including inline suppressions)" unless clear

        events = document.fetch("generation_events")
        array!(events, "generation events")

        events.each do |event|
          fields!(event, %w[file subject source operator reason])
          raise ConfigError, "baseline incomplete generation" unless RunEvidence::SAFE_DROPS.include?(event["reason"])
        end
      end

      def validate_plan
        plan = document.fetch("planned")
        array!(plan, "candidate plan")
        raise ConfigError, "baseline empty candidate plan" if plan.empty?

        plan.each { |entry| fields!(entry, PLAN_FIELDS) }
        results = document.fetch("candidates")
        array!(results, "candidates")

        expected = results.map { |entry| entry.slice(*PLAN_FIELDS) }
        raise ConfigError, "baseline planned results differ" unless
          plan.sort_by { |entry| entry.fetch("id") } == expected.sort_by { |entry| entry.fetch("id") }
      end
    end
  end
end
