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

        Selection::GitDiff.verify_ref!(config["since"], root: config.root) if config["since"]
      end

      # Agent mode allows no score gates (one strict exit 0); the json inventory is --dry-run planning only.
      def reject_format_conflicts
        if agent? && (config["threshold"] || gates.any?)
          raise UsageError, "#{config['threshold'] ? '--threshold' : gates.agent_option_name} " \
                            "cannot be combined with --agent"
        end
        return unless @format == "json" && !options[:dry_run]

        raise UsageError, "--format json is the --dry-run mutant inventory; a run summary is --format agent"
      end
    end
  end
end
