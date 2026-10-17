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

      # Once the baselines are timed, a cold coverage build is the last
      # unpriced phase before the mutants: it costs about one more full pass
      # and keeps nothing when the budget cuts it off, so a resume starts it
      # from zero again. Refuse up front when the remaining budget cannot
      # cover that pass, naming the shortfall and the remedies (#427).
      def refuse_unaffordable_coverage_build(store, files, baseline_elapsed = @baseline_elapsed,
                                             completed_passes = @completed_baseline_passes)
        return unless config["max_duration"]
        return if store.reusable?(files)
        return if completed_passes.to_i.zero?

        per_pass = baseline_elapsed / completed_passes
        remaining = config["max_duration"] - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @run_started)
        # A spent budget is the existing stop path's news, and an untimed
        # (zero-second) baseline carries no estimate to project from.
        return if remaining <= 0 || per_pass <= 0
        return if remaining >= per_pass

        needed = per_pass - remaining
        raise BudgetPhaseTimeout,
              "the --max-duration budget cannot cover the coverage map build: baseline passes took about " \
              "#{per_pass.round}s each, only #{remaining.round(1)}s remain, and a cold build needs about one " \
              "more full pass and keeps nothing when it is cut off. Re-run with --max-duration about " \
              "#{needed.round}s higher, fewer --baseline-passes, or once without --max-duration so the " \
              "coverage cache is built for later --incremental runs"
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
