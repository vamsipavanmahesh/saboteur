# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "mutation_text"
require_relative "survivor_classification"
require_relative "survivor_list"

module Saboteur
  module Reporter
    # Default whole-project findings (D1): the one-line-per-finding list the
    # --quiet report popularised, then full blocks for the top
    # SurvivorRanking picks only, then a dim closer naming the rest. A
    # --since run or --details keeps the full block list.
    class DefaultFindings
      # Blocks a default run expands; the closer counts what is left out.
      TOP_BLOCKS = 3

      # Two lines: the fixed text alone is 87 columns at rest; keep it inside 80.
      CLOSER = "... %<more>d more %<findings>s - saboteur survivors .saboteur/report.json,\nor re-run with --details"

      def initialize(out, palette, all_mutants: false, details: false,
                     whole_suite_map: SurvivorList::NO_WHOLE_SUITE_LOOKUP, run_map: nil)
        @out = out
        @palette = palette
        @all_mutants = all_mutants
        @details = details
        @whole_suite_map = whole_suite_map
        @run_map = run_map
      end

      def call(report, ranked)
        live = ranked.select(&:unignored_survivor?)
        return full(report, ranked) if @details || report.diff? || live.empty?

        @out.puts(list_lines(report, live))
        @out.puts
        SurvivorList.new(@out, @palette, all_mutants: @all_mutants, limit: TOP_BLOCKS,
                                         whole_suite_map: @whole_suite_map, run_map: @run_map).call(report, ranked)
        more = finding_count(report, live) - TOP_BLOCKS
        findings = "finding#{'s' unless more == 1}"
        @out.puts @palette.paint(:dim, format(CLOSER, more:, findings:)) if more.positive?
        @out.puts
      end

      private

      # --details and --since runs: every finding expanded, exactly the
      # pre-D1 default.
      def full(report, ranked)
        SurvivorList.new(@out, @palette, all_mutants: @all_mutants,
                                         whole_suite_map: @whole_suite_map, run_map: @run_map).call(report, ranked)
        @out.puts unless report.survivors.empty?
      end

      # The quiet list's line shape: path:line subject, label and digest,
      # sibling mutants on the statement collapsed to a count (#1126/#1133).
      def list_lines(report, live)
        groups(report, live).map do |(path, line, subject_id), results|
          first, *rest = results
          label = SurvivorClassification.label(first)
          text = "#{path}:#{line} #{subject_id}#{" [#{label}]" if label} - #{first.digest}"
          rest.any? ? "#{text} (+#{rest.size} more)" : text
        end
      end

      # --all-mutants gives every survivor its own block, so the closer
      # counts mutants rather than statements.
      def finding_count(report, live)
        @all_mutants ? live.size : groups(report, live).size
      end

      def groups(report, live)
        live.group_by do |result|
          [relative(result.subject.file, report.root), MutationText.line(result), result.subject.id]
        end
      end

      def relative(file, root)
        file.delete_prefix("#{root}/")
      end
    end
  end
end
