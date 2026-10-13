# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  module Checks
    # Compares --base with the checkout's local origin/main. A difference does not fail the run (a branch
    # may trail main) but it is shown. Freshness against GitHub is never established here.
    class BaseSnapshot
      def initialize(repository:, base:)
        @repository = repository
        @base = base
      end

      def call(_context = nil)
        snapshot = @repository.origin_main_snapshot
        return result(:not_applicable, "no local origin/main to compare; base freshness unverified") unless snapshot
        return result(:passed, nil) if snapshot == @base

        result(:review_required,
               "--base #{@base} differs from local origin/main #{snapshot}; confirm which is current main")
      end

      private

      def result(status, reason)
        CheckResult.new(name: "base_snapshot", status: status, reason: reason)
      end
    end
  end
end
