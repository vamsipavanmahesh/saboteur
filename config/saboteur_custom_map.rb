# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Specs for the lib files whose names break the conventional mirror, so the
# default test inference covers every mutated file and c.test_selection can
# stay at its default instead of :all.
SABOTEUR_CUSTOM_MAP = {
  # The gem entry point (requires + Saboteur.configure).
  "lib/saboteur.rb" => ["spec/saboteur/config_file_spec.rb", "spec/saboteur/install_spec.rb"],
  "lib/saboteur/agent_skill.rb" => ["spec/saboteur/cli_agent_spec.rb"],
  "lib/saboteur/cli/help_options.rb" => ["spec/saboteur/help_spec.rb", "spec/saboteur/cli/help_command_spec.rb"],
  "lib/saboteur/cli/presets.rb" => ["spec/saboteur/cli/preset_killpins_spec.rb", "spec/saboteur/cli_spec.rb"],
  "lib/saboteur/cli/run_reporting.rb" => ["spec/saboteur/cli_reporting_spec.rb",
                                          "spec/saboteur/cli/run_output_spec.rb"],
  "lib/saboteur/cli/shard_options.rb" => ["spec/saboteur/cli_shard_spec.rb",
                                          "spec/saboteur/cli/run_validation_spec.rb"],
  # engine.rb has no single mirror: its specs are the whole engine directory.
  "lib/saboteur/engine.rb" => ["spec/saboteur/engine/**/*_spec.rb"],
  "lib/saboteur/engine/coverage_partial.rb" => ["spec/saboteur/engine/coverage_store_partial_use_spec.rb",
                                                "spec/saboteur/engine/partial_invalidation_spec.rb",
                                                "spec/saboteur/engine/partial_merge_spec.rb"],
  "lib/saboteur/engine/coverage_parts.rb" => ["spec/saboteur/engine/coverage_store_parts_spec.rb",
                                              "spec/saboteur/engine/baseline_parts_spec.rb"],
  "lib/saboteur/engine/coverage_shadow.rb" => ["spec/saboteur/engine/coverage_store_shadow_spec.rb",
                                               "spec/saboteur/engine/shadow_run_spec.rb",
                                               "spec/saboteur/engine/shadow_comparison_spec.rb"],
  "lib/saboteur/engine/out_of_scope_guard.rb" => ["spec/saboteur/engine/since_scope_spec.rb",
                                                  "spec/saboteur/engine/gated_run_spec.rb"],
  "lib/saboteur/engine/pipelines.rb" => ["spec/saboteur/engine/external_pipeline_spec.rb",
                                         "spec/saboteur/replay_pipeline_spec.rb",
                                         "spec/saboteur/engine/distribution_wiring_spec.rb"],
  "lib/saboteur/engine/selection_announcement.rb" => ["spec/saboteur/engine/since_scope_spec.rb",
                                                      "spec/saboteur/engine/unscoped_suite_warning_spec.rb",
                                                      "spec/saboteur/engine/gated_run_spec.rb"],
  "lib/saboteur/frameworks/database_hosts.rb" => ["spec/saboteur/engine/worker_database_cleanup_spec.rb",
                                                  "spec/saboteur/doctor_spec.rb"],
  "lib/saboteur/mutation_source/edit.rb" => ["spec/saboteur/mutation_source/mutation_spec.rb",
                                             "spec/saboteur/mutation_source/entry_edits_spec.rb"],
  "lib/saboteur/reporter/agent_clipping.rb" => ["spec/saboteur/reporter/agent_edges_spec.rb",
                                                "spec/saboteur/reporter/agent_spec.rb",
                                                "spec/saboteur/reporter/agent_pins_spec.rb"],
  "lib/saboteur/reporter/agent_summary.rb" => ["spec/saboteur/reporter/agent_spec.rb",
                                               "spec/saboteur/reporter/agent_pins_spec.rb",
                                               "spec/saboteur/reporter/agent_edges_spec.rb"]
}.freeze
