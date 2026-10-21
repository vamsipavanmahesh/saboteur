# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../engine/result_cache"

module Saboteur
  module Reporter
    # Verdict-reuse feedback: named whenever the run opted into reuse, since a
    # silent run leaves the flag's effect unknowable. A plain run (no reuse
    # mechanism, nothing reused) stays silent. The label is the flag
    # the user typed (--incremental or --resume, Engine#reuse_label). The
    # denominator counts only storable verdicts (Engine::ResultCache::STORED);
    # skips and errors are never cached, so naming them explains a short one.
    class ReuseNote
      def initialize(out)
        @out = out
      end

      def print(report)
        return unless report.results.any? && (report.reuse_label || report.results.any?(&:reused?))

        reused = report.results.count(&:reused?)
        label = report.reuse_label || "--incremental"
        if reused.zero?
          @out.puts "no verdicts reused from earlier runs (#{label}): first #{label} run, " \
                    "or every mutant's inputs changed"
          return
        end

        storable = report.results.count { |result| Engine::ResultCache::STORED.include?(result.status) }
        line = "reused #{reused} of #{storable} verdicts from earlier runs (#{label})"
        reruns = report.results.size - storable
        @out.puts reruns.positive? ? "#{line}; #{reruns} skipped/errored mutant(s) always rerun" : line
      end
    end
  end
end
