# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # Report destinations and text output flags for `saboteur run` (#334).
    module OutputOptions
      private

      def define_output_options(opts)
        opts.on("--score-history PATH", "Append score history JSONL (opt-in)") { |v| set(:score_history, v) }
        opts.on("--json PATH", "Stryker JSON report path") { |v| set(:json_report, v) }
        opts.on("--html PATH", "Self-contained HTML report path") { |v| set(:html_report, v) }
        opts.on("--format FORMAT", %w[text agent json], "text, agent or json (--dry-run inventory)") { |v| @format = v }
        opts.on("--agent", "Same as --format agent") { @format = "agent" }
        opts.on("--verbose", "Text report: also print score split, timings and kill causes;",
                "a crash prints its backtrace") do
          @verbose = true
          set(:verbose, true)
        end
        opts.on("--color [MODE]", %w[always never auto],
                "Colour the text report: always, never or auto (default: auto)") do |v|
          @color = (v || :always).to_sym
        end
        opts.on("--all-mutants", "Text report: list every survived mutant;",
                "default: one finding per statement, with the label mix") { set(:all_mutants, true) }
        opts.on("--no-color", "Deprecated alias for --color=never") { @color = :never }
      end
    end
  end
end
