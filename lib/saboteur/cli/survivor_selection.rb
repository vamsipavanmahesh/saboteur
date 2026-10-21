# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # Everything the --survivors option contributes to a run: the digest
    # selection, the empty-report exit, the engine arguments it rides on.
    module SurvivorSelection
      private

      # Read once: the digests select the mutants, the path names them.
      def survivor_selection
        return nil unless options[:survivors]

        @survivor_selection ||= begin
          report = load_survivor_report(options[:survivors])
          { digests: SurvivorsBrowser.new(report).survivor_digests, source: options[:survivors] }
        end
      end

      # No live survivors to re-run is a healthy suite, not a usage error.
      def survivors_empty_exit
        @out.puts("no unignored survivors in #{options[:survivors]} - nothing to re-run")
        EXIT_OK
      end

      # One palette per stream: each detects colour on its own.
      def engine_arguments(selection)
        arguments = { err: @err,
                      palette: Reporter::Palette.for(@err, mode: @color || :auto, overrides: config["palette"]) }
        arguments[:digest] = options[:id] if options[:id]
        arguments[:survivors] = selection if selection
        arguments[:capture_evidence] = true if config["baseline"]
        arguments[:evidence_files] = [config["baseline"]] if config["baseline"]
        arguments
      end
    end
  end
end
