# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "saboteur/version"

module Saboteur
  class Error < StandardError; end

  # A spec path from the cached coverage map that is not a spec file inside
  # the project: the map is untrusted input (#427, #1286).
  class RefusedSpecPath < Error; end

  # A phase timeout that --max-duration shortened: budget exhaustion, not a
  # broken suite. The engine turns it into the budget partial-report path
  # instead of a phase error (#296).
  class BudgetPhaseTimeout < Error; end

  # Invalid configuration or input files (exit code 2).
  class ConfigError < Error; end

  # Files vanished from the working tree while mutants ran (exit code 3).
  class CanaryTripped < Error
    # Set by the per-mutant probe (the mutant whose run just ended, #235);
    # nil for a subject-end check, whose "most recent mutant" is only the
    # likely cause and must not outrank a per-mutant report (#285).
    attr_reader :culprit_digest

    def initialize(message = nil, culprit_digest: nil)
      @culprit_digest = culprit_digest
      super(message)
    end
  end

  class << self
    # Set while hook files from config load, so they can call Saboteur.hook.
    attr_accessor :current_hooks

    # Registers a lifecycle hook from a hooks file:
    #
    #   Saboteur.hook(:after_fork) { Redis.current.disconnect! }
    #   Saboteur.hook(:around_mutant) { |mutation, run| Timecop.freeze { run.call } }
    def hook(name, callable = nil, &)
      raise Error, "Saboteur.hook is only available while hook files load" unless current_hooks

      current_hooks.register(name, callable, &)
    end
  end
end

require_relative "saboteur/coverage_reads"
require_relative "saboteur/method_calls"
require_relative "saboteur/line_hits"
require_relative "saboteur/hooks"
require_relative "saboteur/mutation_source/base"
require_relative "saboteur/mutation_source/builtin"
require_relative "saboteur/integration/base"
require_relative "saboteur/subject"
require_relative "saboteur/deep_source"
require_relative "saboteur/refinement_activations"
require_relative "saboteur/subject_finder"
require_relative "saboteur/attribute_finder"
require_relative "saboteur/constant_subject"
require_relative "saboteur/constant_subject_finder"
require_relative "saboteur/constant_reads"
require_relative "saboteur/mutation_source/constant_literals"
require_relative "saboteur/execution/protocol"
require_relative "saboteur/execution/process_table"
require_relative "saboteur/execution/process_tree"
require_relative "saboteur/execution/marker_sweep"
require_relative "saboteur/execution/supervisor"
require_relative "saboteur/execution/reevaluator"
require_relative "saboteur/execution/wrapper"
require_relative "saboteur/execution/runner"
require_relative "saboteur/execution/bundle_gemfile_pin"
require_relative "saboteur/execution/gemfile_path_sources"
require_relative "saboteur/execution/external_runner"
require_relative "saboteur/execution/worker_pool"
require_relative "saboteur/execution/fork_readiness"
require_relative "saboteur/execution/sandbox"
require_relative "saboteur/execution/seatbelt"
require_relative "saboteur/selection/coverage_map"
require_relative "saboteur/selection/external_test_map"
require_relative "saboteur/selection/recorder"
require_relative "saboteur/selection/trace_recorder"
require_relative "saboteur/selection/git_diff"
require_relative "saboteur/selection/source_scope"
require_relative "saboteur/result"
require_relative "saboteur/custom_map"
require_relative "saboteur/gates"
require_relative "saboteur/config"
require_relative "saboteur/ignore_list"
require_relative "saboteur/frameworks/rails"
require_relative "saboteur/reporter/diff"
require_relative "saboteur/reporter/findings"
require_relative "saboteur/reporter/review_comments"
require_relative "saboteur/reporter/agent"
require_relative "saboteur/working_tree"
require_relative "saboteur/dirty_tree_warning"
require_relative "saboteur/agent_skill"
require_relative "saboteur/reporter/terminal"
require_relative "saboteur/reporter/stryker"
require_relative "saboteur/reporter/survivor_classification"
require_relative "saboteur/reporter/html"
require_relative "saboteur/environment_hints"
require_relative "saboteur/engine"
