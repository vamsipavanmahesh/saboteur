# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # --flaky-check (#1167): a verdict that flipped on the reordered rerun is
    # unverified, outside the score. The run was not stopped by a budget, so
    # it is not exit 4, but it cannot go green either.
    module FlakyExit
      private

      def flaky_disagreement?(report)
        flaky = report.results.select(&:flaky?)
        return false if flaky.empty?

        @err.puts("saboteur: #{flaky.size} mutant#{'s' unless flaky.one?} changed verdict on the --flaky-check " \
                  "reordered rerun (#{flaky.first(3).map(&:digest).join(', ')}), so they are unverified: " \
                  "your tests depend on run order; fix that and run again")
        true
      end
    end
  end
end
