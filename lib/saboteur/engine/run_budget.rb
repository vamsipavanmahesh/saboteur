# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # The --max-duration wall-clock budget (#245). The clock anchors at
    # engine entry, so boot, baselines and the coverage map spend it too;
    # schedulers get an absolute deadline so a spent budget also stops a
    # long subject between mutants.
    module RunBudget
      private

      def start_budget_clock(started)
        @run_started = started if config["max_duration"]
      end

      # The whole run is budgeted, baselines included: an oversized
      # baseline spends the budget by itself.
      def budget_exceeded?
        return false unless config["max_duration"]

        exceeded = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @run_started >= config["max_duration"]
        announce_budget_once if exceeded
        exceeded
      end

      # Absolute monotonic deadline shared with the schedulers (forked
      # workers inherit it): a subject's remaining mutants stop once it
      # passes, so the overshoot after a spent budget stays under one
      # mutant deadline.
      def budget_deadline
        config["max_duration"] && (@run_started + config["max_duration"])
      end

      def announce_budget_once
        return if @budget_announced

        @budget_announced = true
        @diagnostics.inform("--max-duration reached: stopping before the next subject; the report marks it partial")
      end
    end
  end
end
