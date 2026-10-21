# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # What the clean screen's header, reports line and phase lines need from
    # the run: the real scope, the HTML report's path when it was written, and
    # the phase costs the engine recorded once (Report#phase_timings, shared
    # with the speed footer).
    module CleanScreenContext
      private

      def clean_screen_context(html_path, report)
        { scope: config["since"] ? "--since #{config['since']}" : "whole project",
          html_report: html_path && relative_to_root(html_path),
          **phase_lines(report.phase_timings) }
      end

      def phase_lines(timings)
        return {} unless timings&.baseline_passes && timings.map_tests

        { baseline: { passes: timings.baseline_passes, seconds: timings.baseline_seconds },
          coverage: { tests: timings.map_tests, seconds: timings.map_seconds, cached: timings.map_cached },
          mutant_phase: { seconds: timings.mutants_seconds } }
      end

      def relative_to_root(path)
        File.expand_path(path).delete_prefix(File.join(File.realpath(config.root), ""))
      end
    end
  end
end
