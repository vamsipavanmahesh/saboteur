# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"

module Saboteur
  class CLI
    # The `saboteur run --baseline PATH` gate: loading the accepted baseline
    # (fail fast, before the suite boots) and mapping the comparison to the
    # run's exit code. Mixed into the CLI, which supplies `config`.
    module BaselineGate
      private

      # The --baseline comparison replaces the ordinary quality-gate verdict.
      def exit_code(report) = config["baseline"] ? baseline_verdict(report) : super

      # --baseline: the comparison against the accepted baseline is the
      # verdict. Accepted legacy survivors no longer fail the run; new
      # survivors or a score drop beyond --epsilon do (exit 1). An
      # incompatible baseline is a usage error; an incomplete comparison
      # means the run's own evidence cannot judge it (exit 3).
      def baseline_verdict(report)
        gate = baseline_gate(report)
        raise ConfigError, gate.comparison.issues.join("; ") if gate.incompatible?
        return EXIT_TOOL if gate.incomplete?

        gate.failed? ? EXIT_SURVIVORS : EXIT_OK
      end

      def baseline_gate(report)
        @baseline_gate ||= begin
          path = config["baseline"]
          if Digest::SHA256.file(path).hexdigest != @baseline_digest
            raise ConfigError, "baseline changed during the run"
          end

          Baseline::RunGate.build(manifest: baseline_manifest, report: report, epsilon: config["epsilon"] || 0.0)
        end
      end

      # The accepted baseline at config["baseline"], loaded once (and before
      # the suite boots) so a missing or corrupt file fails fast as a usage
      # error naming the fix.
      def baseline_manifest
        return @baseline_manifest if @baseline_manifest

        path = config["baseline"]
        raise UsageError, "--baseline file not found: #{path} - run `saboteur baseline propose` first" unless
          File.exist?(path)

        @baseline_manifest, @baseline_digest = Baseline::Loader.call(path)
        @baseline_manifest
      rescue ConfigError => e
        raise UsageError, "#{e.message} - run `saboteur baseline propose` first"
      end
    end
  end
end
