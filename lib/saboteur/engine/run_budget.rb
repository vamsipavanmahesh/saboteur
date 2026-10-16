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
        @run_started = started
      end

      # The whole run is budgeted, baselines included: an oversized
      # baseline spends the budget by itself.
      def budget_exceeded?
        return false unless config["max_duration"]

        exceeded = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @run_started >= config["max_duration"]
        announce_budget_once if exceeded
        exceeded
      end

      # A phase admitted inside the budget still gets only the time left
      # in it: baseline passes and coverage builds cap at the deadline.
      def budget_capped_timeout(timeout)
        deadline = budget_deadline
        return timeout unless deadline

        (deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)).clamp(0.0, timeout)
      end

      # Absolute monotonic deadline shared with the schedulers (forked
      # workers inherit it): a subject's remaining mutants stop once it
      # passes, so the overshoot after a spent budget stays under one
      # mutant deadline.
      def budget_deadline
        config["max_duration"] && (@run_started + config["max_duration"])
      end

      # Boot and baselines can spend the budget by themselves: stop before
      # an expensive cold coverage build and mark every selected subject
      # unrun.
      def abandon_for_budget?(subjects)
        return false unless budget_exceeded?

        @early_stop = EarlyStop.new(reason: "max_duration", unreached: subjects.map(&:id), truncated: [],
                                    unverified: [])
        true
      end

      def announce_budget_once
        return if @budget_announced

        @budget_announced = true
        @diagnostics.inform("--max-duration reached: stopping before the next subject; the report marks it partial")
      end
    end
  end
end
