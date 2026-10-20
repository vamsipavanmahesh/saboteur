# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # Agent-mode provenance: the record a JSON report carries so its rerun
    # and replay commands reproduce the run exactly (#334). Extracted from
    # CLI; the builder and its settings helpers are private to the mixin.
    module AgentProvenance
      private

      def agent_provenance(report, tree, engine)
        Reporter::Agent::Provenance.new(
          ref: config["since"], seed: report.seed, head: tree.head, working_tree: tree.label,
          changed_files: tree.changed_files, mode: agent_mode, json_report: config.path("json_report"),
          subjects: Array(config["subjects"]), tests: Array(engine.guessed_tests || config["tests"]),
          sources: @sources || [],
          config_path: options[:config], digest: options[:id], cache: config["cache"],
          incremental: config["incremental"], settings: agent_settings, typed_settings: typed_settings,
          referenced: report.referenced
        )
      end

      # The settings keys typed on the command line: a typed empty operator
      # list may clear a config value, so the generated commands keep it.
      def typed_settings = options.keys & Reporter::Agent::Commands::SETTING_FLAGS.keys

      # A whole-suite run records its scope as --all, so the generated rerun
      # and replay commands do not default back to inference (which can exit
      # 2 in a project with a spec-less source file).
      def agent_settings
        settings = options.slice(*Reporter::Agent::Commands::SETTING_FLAGS.keys)
                          .merge(operators: config["operators"], exclude_operators: config["exclude_operators"])
        # The effective mode: named tests win over a configured whole-suite
        # selection by precedence, so all is recorded only when no tests
        # resolved - otherwise the follow-up commands would carry both --all
        # and --test, which the CLI rejects.
        settings[:all] = true if (config["all"] || config["test_selection"] == "all") && config["tests"].empty?
        # CLI-only switches that change candidate availability or boot, so a
        # printed rerun/replay must keep them (config-file settings like
        # arid/hazard patterns, whole-file, require, rspec_args and rails ride
        # along through --config or the default config path).
        settings[:allow_hazardous] = true if options[:allow_hazardous]
        settings[:allow_focus] = true if options[:allow_focus]
        # An explicit false (--no-max-duration-ok over a config true) is a
        # setting too: dropping it would silently re-enable the config value.
        settings[:max_duration_ok] = options[:max_duration_ok] unless options[:max_duration_ok].nil?
        settings
      end

      def agent_mode
        return "replay" if options[:id]
        return "diff" if config["since"]

        @sources&.any? ? "files" : "full"
      end
    end
  end
end
