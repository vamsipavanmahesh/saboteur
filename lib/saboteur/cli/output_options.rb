# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # Report destinations and text output flags for `saboteur run` (#334).
    module OutputOptions
      private

      def define_output_options(opts)
        define_report_destination_options(opts)
        define_text_report_options(opts)
      end

      # Report destinations and the format switch.
      def define_report_destination_options(opts)
        opts.on("--score-history PATH", "Append score history JSONL (opt-in)") { |v| set(:score_history, v) }
        opts.on("--json PATH", "Stryker JSON report path") { |v| set(:json_report, v) }
        opts.on("--html PATH", "Self-contained HTML report path") { |v| set(:html_report, v) }
        opts.on("--format FORMAT", %w[text agent json], "text, agent or json (--dry-run inventory)") { |v| @format = v }
        opts.on("--agent", "Same as --format agent") { @format = "agent" }
      end

      # Flags that shape the text report. Kept under the per-method mutant cap
      # by the destination/text split above.
      def define_text_report_options(opts)
        opts.on("--verbose", "Text report: also print score split, timings and kill causes;",
                "a crash prints its backtrace") do
          @verbose = true
          set(:verbose, true)
        end
        opts.on("--color [MODE]", %w[always never auto],
                "Colour the text report: always, never or auto (default: auto)") do |v|
          @color = (v || :always).to_sym
        end

        # PR6: CI and pre-push output - the findings and the verdict only.
        opts.on("--quiet", "Text report: print only the findings and the verdict;",
                "no effect with --format json/agent; ignores --all-mutants") do
          @quiet = true
          set(:quiet, true)
        end
        opts.on("--all-mutants", "Text report: list every survived mutant;",
                "default: one finding per statement, with the label mix") { set(:all_mutants, true) }
        # D1: the default whole-project report lists findings and expands the
        # top three; --details restores a block for every finding.
        opts.on("--details", "Text report: full blocks for every finding;",
                "default: one-line list plus the top 3 blocks") { set(:details, true) }
        opts.on("--no-color", "Deprecated alias for --color=never") { @color = :never }
      end
    end
  end
end
