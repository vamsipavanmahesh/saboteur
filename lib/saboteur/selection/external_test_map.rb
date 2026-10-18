# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Selection
    # The --test-command mode has no coverage map (#140): the command runs
    # the whole suite per mutant, so every subject reads as covered by the
    # one pseudo-test and no recorded timing exists, leaving the per-mutant
    # timeout to the config's baseline_timeout.
    class ExternalTestMap
      def tests = [Execution::ExternalRunner::PSEUDO_TEST]

      def tests_for(_subject) = tests

      def tests_for_edit(_subject, _lines) = tests

      def tests_for_branches(_subject, _edits) = tests

      def ran_at_load?(_file, _lines) = false

      # No coverage map exists in external mode, so what ran at boot is
      # unknowable: never claim the boot-once signature (#575).
      def boot_once?(_subject) = false

      # No boot happens in this mode, so nothing can have run only at load.
      def called_only_at_load?(_file, _line) = false

      def recorded_runtime(_tests) = nil
    end
  end
end
