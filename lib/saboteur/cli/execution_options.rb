# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # Execution, cache and hazard flags for `saboteur run` (#334).
    module ExecutionOptions
      private

      def define_execution_options(opts)
        opts.on("--timeout-factor N", Float, "Multiple of baseline runtime (default 3)") { |v| set(:timeout_factor, v) }
        opts.on("--jobs N", Integer, "Concurrent workers (default 1)") { |v| set(:jobs, v) }
        add_run_budget_options(opts)
        opts.on("--config PATH", "Config file (default config/saboteur.rb)") { |v| set(:config, v) }
        opts.on("--integration NAME", "Test adapter (rspec)") { |v| set(:integration, v) }
        opts.on("--reeval STRATEGY", Execution::Reevaluator::STRATEGIES, "class_eval or nesting") { |v| set(:reeval, v) }
        opts.on("--no-cache", "Rebuild the coverage map") { set(:cache, false) }
        opts.on("--allow-hazardous",
                "Also run mutants inside destructive calls (rm_rf, system, ...)") { set(:allow_hazardous, true) }
        opts.on("--fail-fast",
                "Stop after the first subject with a survivor (needs --jobs 1)") { set(:fail_fast, true) }
        opts.on("--incremental", "Reuse earlier verdicts whose inputs did not change") { set(:incremental, true) }
        opts.on("--allow-focus", "Run even when a focus filter (fit, fdescribe, :focus) narrows the suite") do
          set(:allow_focus, true)
        end
        opts.on("--all", "Run the whole configured test suite instead of inferring the specs named after the " \
                         "mutated files") { set(:all, true) }
        opts.on("--test-command CMD", "Run CMD per mutant in the project root; exit 0 means the mutant survived. " \
                                      "For apps that cannot load in this Ruby; much slower, serial, no coverage") do |v|
          set(:test_command, v)
        end
        opts.on("--[no-]guess-tests", "Deprecated alias: inferred specs are already the default; " \
                                      "--no-guess-tests warns and is ignored - use --all for the whole suite") do |v|
          set(:guess_tests, v)
        end
      end
    end
  end
end
