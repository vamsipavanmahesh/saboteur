# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # A whole-suite run (--all, c.test_selection = :all, or a --since diff
    # with nothing to infer from) runs the loaded suite for the baseline
    # checks; a cold coverage cache adds one more pass. Say so - with the
    # example count and the real pass count - before those hours pass; past
    # a size threshold, add the way to scope it (#260). The check count
    # comes from c.baseline_passes (#55).
    module UnscopedSuiteWarning
      # A suite this size pays hours for an unscoped run; below it the cost
      # summary alone is enough, without the --test lecture (#260).
      COSTLY_SUITE_EXAMPLES = 1_000
      REUSED_MAP_NOTE = "; the cached coverage map is reused"

      def self.call(config:, diagnostics:, integration:, full_passes:)
        return unless config["tests"].empty?
        return unless config["since"] || config["all"] || config["test_selection"] == "all"

        examples = integration.all_tests.size
        coverage = full_passes == config["baseline_passes"] ? REUSED_MAP_NOTE : " + 1 coverage map build"
        message = "running the loaded suite unscoped: #{examples} examples in #{integration.test_files.size} " \
                  "spec files; #{full_passes} full passes (#{checks_label(config)}#{coverage})."
        if examples >= COSTLY_SUITE_EXAMPLES
          message += "\n  Fix: pass --test to run only the specs you name: faster, but a mutant of a changed " \
                     "method is then killed only by those specs, so specs elsewhere that call this code are not run. " \
                     "The default inferred selection runs the specs named after the mutated files, " \
                     "a guess that can miss specs elsewhere."
        end
        diagnostics.warn(message)
        diagnostics.inform(message)
      end

      def self.checks_label(config)
        "#{config['baseline_passes']} baseline check#{'s' unless config['baseline_passes'] == 1}"
      end
    end
  end
end
