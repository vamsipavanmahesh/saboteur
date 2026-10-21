# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # The usage errors `saboteur run` finds before the target boots: option
    # combinations that contradict each other (#334). Extracted from CLI.
    module RunValidation
      private

      # Contradictory selection flags are a usage error before any file or
      # repository check: --test wins over inference by precedence, but only
      # one of them may be named. Config-file combinations are not errors:
      # --test wins there, so generated commands stay valid over any config.
      def reject_test_selection_conflicts
        raise UsageError, "--all cannot be combined with --test" if options[:all] && options[:tests]&.any?

        reject_test_command_conflicts
        raise UsageError, "--all cannot be combined with --guess-tests" if options[:all] && options[:guess_tests]
        return unless options[:guess_tests] && options[:tests]&.any?

        raise UsageError, "--guess-tests cannot be combined with --test"
      end

      # --test-command replaces the whole in-process test machinery: test
      # selection, coverage, parallelism and the sandbox do not apply.
      def reject_test_command_conflicts
        return unless options[:test_command]

        # options[:tests] is nil or a non-empty list, so truthiness is the check.
        raise UsageError, "--test-command cannot be combined with --test" if options[:tests]
        raise UsageError, "--test-command cannot be combined with --incremental" if options[:incremental]
      end

      # Usage errors found before the target boots.
      def validate_run_options
        reject_format_conflicts
        validate_shard_options
        raise UsageError, "--ignore-empty applies to --since runs" if config["ignore_empty"] && !config["since"]

        validate_baseline_options

        Selection::GitDiff.verify_ref!(config["since"], root: config.root) if config["since"]
      end

      # The run gate needs fresh whole-scope execution evidence, so it
      # refuses every flag the evidence capture rejects, up front. A missing
      # or corrupt baseline file is a usage error before the suite boots.
      def validate_baseline_options
        raise UsageError, "--epsilon applies with --baseline" if config["epsilon"] && !config["baseline"]
        if config["epsilon"] && !(0.0..100.0).cover?(config["epsilon"])
          raise UsageError, "--epsilon must be between 0 and 100"
        end
        return unless config["baseline"]

        conflicts = %w[since incremental threshold resume shard].select { |key| config[key] }
        conflicts << "id" if options[:id]
        unless conflicts.empty?
          flags = conflicts.map { |key| "--#{key}" }.join(", ")
          raise UsageError, "--baseline cannot be combined with #{flags}"
        end
        baseline_manifest
      end

      # Agent mode allows no score gates (one strict exit 0); the json inventory is --dry-run planning only.
      def reject_format_conflicts
        # --quiet prints only the findings and the verdict; --verbose adds
        # the debug statistics. One output cannot be both.
        raise UsageError, "--quiet cannot be combined with --verbose" if options[:quiet] && options[:verbose]

        if agent? && (config["threshold"] || config["baseline"] || gates.any?)
          raise UsageError, "#{agent_gate_name} cannot be combined with --agent"
        end
        return unless @format == "json" && !options[:dry_run]

        raise UsageError, "--format json is the --dry-run mutant inventory; a run summary is --format agent"
      end

      def agent_gate_name
        return "--threshold" if config["threshold"]
        return "--baseline" if config["baseline"]

        gates.agent_option_name
      end
    end
  end
end
