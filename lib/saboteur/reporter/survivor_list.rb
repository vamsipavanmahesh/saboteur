# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "mutation_text"
require_relative "survivor_hints"
require_relative "survivor_classification"

module Saboteur
  module Reporter
    # Survivors grouped by file, then method, then line. The source line and
    # the tests that covered it are printed once; each mutation is one compact
    # line: operator, original -> replacement, digest.
    class SurvivorList
      MAX_PASSING_TESTS = 5

      def initialize(out, palette, all_mutants: false, classifier: SurvivorClassification)
        @out = out
        @palette = palette
        @all_mutants = all_mutants
        @classifier = classifier
      end

      # Every survivor, in report order; the grouping keeps them readable.
      def call(report, survivors)
        return if survivors.empty?

        @out.puts "Survivors (#{survivors.size}):"
        survivors.group_by { |result| result.subject.file }.sort_by { |file, _| file }.each do |file, in_file|
          file_section(report, relative(file, report.root), in_file)
        end
        @out.puts "\n#{@palette.paint(:dim, SurvivorHints::CAVEAT)}" if survivors.any? { |result| hint_for(result) }
      end

      private

      def file_section(report, path, in_file)
        @out.puts "\n#{@palette.paint(:bold, path)}"
        in_file.group_by { |result| result.subject.id }.each do |subject_id, in_subject|
          @out.puts "  #{subject_id}"
          lines(report, path, in_subject)
        end
      end

      def lines(report, path, in_subject)
        in_subject.group_by { |result| MutationText.line(result) }.sort.each do |line, on_line|
          first = on_line.first
          @out.puts "    #{path}:#{line} in #{first.subject.id}"
          @out.puts "      #{@palette.paint(:dim, "#{line}:")} #{source_line(first, line)}"
          if @all_mutants
            evidence_groups(report, on_line).each { |group| evidence_group(report, path, group) }
          else
            live, ignored = on_line.partition { |result| result.ignored.nil? }
            statement_finding(live) unless live.empty?
            ignored.each { |result| mutation(result) }
          end
        end
      end

      # Default view (#1065): one finding per statement - how many mutants
      # survive here and the mix of their classification labels, with the
      # covering tests once. --all-mutants restores the per-mutant list.
      def statement_finding(on_line)
        count = "#{on_line.size} #{on_line.one? ? 'mutant' : 'mutants'}"
        mix = on_line.group_by { |result| @classifier.label(result) || "unlabeled" }
                     .sort_by { |label, _| label }
                     .map { |label, group| "#{group.size} #{label}" }
                     .join(", ")
        @out.puts "      #{@palette.paint(:red, '-')} #{count}: #{mix}"
        tests_line(on_line.flat_map(&:covered_by).uniq, on_line.first.reused?,
                   ran: on_line.flat_map { |result| result.executed || result.covered_by }.uniq)
        digests = on_line.map(&:digest)
        more = digests.size - 3
        suffix = " (+#{more} more in the JSON report)" if more.positive?
        @out.puts "        #{digests.first(3).join(' ')}#{suffix}"
      end

      # Mutants on one line share the printed evidence when it names the
      # same tests: the covering-test list is compared as a set (#502), so
      # one line's mutants no longer reprint an identical block only because
      # the run measured the killer order per mutant. Reuse and changed
      # lines still group exactly. Each run of neighbours with the same key
      # is one group and shares evidence above its own mutations; evidence
      # that repeats after another group is printed again, which keeps the
      # ranked order. The block prints in the first mutant's run order.
      def evidence_groups(report, on_line)
        on_line.chunk { |result| [result.covered_by.uniq.sort, result.reused?, report.changed_lines_for(result)] }
               .map(&:last)
      end

      def evidence_group(report, path, group)
        first = group.first
        changed_lines(report, path, first)
        passing_tests(first)
        group.each { |result| mutation(result) }
      end

      def source_line(result, line)
        result.subject.file_source.lines[line - 1].to_s.strip
      end

      def mutation(result)
        change = if MutationText.removal?(result)
                   "removes #{MutationText.original(result)}"
                 else
                   "#{MutationText.original(result)} -> #{@palette.paint(:green, MutationText.replacement(result))}"
                 end
        text = "      #{@palette.paint(:red, '-')} #{result.mutation.operator} " \
               "#{change} #{result.digest}"
        label = @classifier.label(result)
        text += @palette.paint(:cyan, " [#{label}]") if label
        text += " (ignored: #{result.ignored})" if result.ignored
        @out.puts text
        hint(result)
      end

      def hint(result)
        text = hint_for(result)
        @out.puts "        #{@palette.paint(:cyan, 'hint:')} #{text}" if text
      end

      def hint_for(result)
        return nil if result.ignored

        SurvivorHints.for(result.mutation.operator, coarse: result.mutation.coarse)
      end

      # The tests that ran with the mutant applied and still passed: the
      # missing assertion belongs in one of them. They are listed likeliest
      # killers first, the order the run used. Line coverage can overstate which
      # tests exercise the line, so the list is a lead, not proof.
      def passing_tests(result)
        tests_line(result.covered_by, result.reused?, ran: (result.executed || result.covered_by).uniq)
      end

      # ran is which of the covering tests actually executed against the
      # mutant (nil recorded as covered_by). When fewer ran than covered the
      # line, the survivor rests on the ran subset - say so and name the rest.
      def tests_line(tests, reused, ran: tests)
        return if tests.empty?

        unrun = tests - ran
        return ran_line(tests, unrun, reused) if unrun.any? && (ran - tests).empty?

        @out.puts "      #{tests.size} #{tests.one? ? 'test' : 'tests'} covered this line and " \
                  "#{reused ? 'passed in an earlier run (--incremental)' : 'still passed'} " \
                  "(the missing check may belong in one of them):"
        tests.first(MAX_PASSING_TESTS).each { |name| @out.puts "        #{name}" }
        more = tests.size - MAX_PASSING_TESTS
        @out.puts "        ... #{more} more in the JSON report (coveredBy)" if more.positive?
      end

      def ran_line(tests, unrun, reused)
        ran = tests - unrun
        @out.puts "      #{ran.size} of the #{tests.size} tests that covered this line " \
                  "#{reused ? 'passed in an earlier run (--incremental)' : 'ran and still passed'} " \
                  "(the missing check may belong in one of them):"
        ran.first(MAX_PASSING_TESTS).each { |name| @out.puts "        #{name}" }
        more = ran.size - MAX_PASSING_TESTS
        @out.puts "        ... #{more} more in the JSON report (executed)" if more.positive?
        suffix = unrun.size > 3 ? " (+#{unrun.size - 3} more)" : ""
        @out.puts "      did not run: #{unrun.first(3).join(', ')}#{suffix}"
      end

      # In diff mode: the changed lines this mutant touches.
      def changed_lines(report, path, result)
        lines = report.changed_lines_for(result)
        return if lines.empty?

        shown = lines.first(3).map { |line| "#{path}:#{line}" }.join(", ")
        more = lines.size - 3
        @out.puts "      changed #{lines.one? ? 'line' : 'lines'}: #{shown}#{" (+#{more} more)" if more.positive?}"
      end

      def relative(file, root)
        file.delete_prefix("#{root}/")
      end
    end
  end
end
