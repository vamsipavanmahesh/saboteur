# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Owns the host process's Coverage state across a run: suspends after
    # boot, and at the end resumes only its own suspension. A CLI process
    # exits right after, so resume matters to hosts that embed the engine -
    # a spec, or the dogfood's own coverage-map build (#254).
    class CoverageGuard
      def initialize(diagnostics)
        @diagnostics = diagnostics
      end

      def suspend
        @was_running = Coverage.state == :running
        Coverage.suspend if @was_running
      end

      # Best-effort: a host that disturbed Coverage mid-run gets a warning,
      # never a masked run outcome.
      def resume
        Coverage.resume if @was_running && Coverage.state == :suspended
      rescue StandardError => e
        @diagnostics.warn("coverage resume failed: #{e.class}: #{e.message}\n  " \
                          "Fix: remove whatever suspends Ruby's Coverage mid-run " \
                          "(another coverage tool such as SimpleCov)")
      end
    end
  end
end
