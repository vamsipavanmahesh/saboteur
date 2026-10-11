# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Plain-text summary: counts per status, score, timings, skip reasons,
    # errors, then a unified diff for each survivor.
    class Terminal
      MAX_ERRORS = 10
      MAX_PASSING_TESTS = 5

      def initialize(out)
        @out = out
      end

      def call(report)
        summary(report)
        skipped_subjects(report)
        warnings(report)
        errors(report)
        survivors(report)
      end

      private

      def summary(report)
        seed = report.seed && ", seed #{report.seed} (repeat with --seed #{report.seed})"
        @out.puts "saboteur #{VERSION}: #{report.subjects.size} subjects, #{report.results.size} mutants, " \
                  "wall #{format('%.2f', report.wall_time)} s#{seed}"
        @out.puts status_line(report)
        details(report)
      end

      def status_line(report)
        c = report.counts
        survived = "survived #{c[:survived]}"
        ignored = report.survivors.size - report.unignored_survivors.size
        survived += " (#{ignored} ignored)" if ignored.positive?
        "killed #{c[:killed]}  #{survived}  timeout #{c[:timeout]}  resource limit #{c[:resource_limit]}  " \
          "error #{c[:error]}  skipped #{c[:skipped]}"
      end

      def details(report)
        score = report.score
        @out.puts "score #{score ? format('%.1f %%', score * 100) : 'n/a'} " \
                  "(killed+timeout)/(killed+survived+timeout); errors, resource limits and skips excluded"
        mean = report.mean_runtime
        @out.puts "mean time per executed mutant #{format('%.3f', mean)} s" if mean
        @out.puts "invalid mutations dropped (did not parse): #{report.invalid_mutations}" if
          report.invalid_mutations.positive?
        report.skip_reasons.each { |reason, count| @out.puts "skipped: #{reason}: #{count}" }
        reused = report.results.count(&:reused?)
        @out.puts "reused #{reused} of #{report.results.size} verdicts from earlier runs (--incremental)" if
          reused.positive?
        @out.puts "kills rejected by unchanged-method check: #{report.rejected_kills}"
        kill_causes(report)
      end

      # How many kills came from a failed check and how many from a crash, and
      # which operators mostly kill by crashing (their score says less).
      def kill_causes(report)
        killed = report.results.select { |result| result.status == :killed && result.kill_cause }
        return if killed.empty?

        crashes = killed.select(&:crash_kill?)
        @out.puts "kills: #{killed.size - crashes.size} by a failed assertion, #{crashes.size} by a crash" \
                  "#{crash_classes(crashes)}"
        @out.puts "crash kills by operator: #{crashes_by_operator(killed)}" if crashes.any?
      end

      def crash_classes(crashes)
        return "" if crashes.empty?

        counts = crashes.map(&:kill_cause).tally.sort_by { |_, count| -count }
        " (#{counts.map { |name, count| "#{name} #{count}" }.join(', ')})"
      end

      def crashes_by_operator(killed)
        parts = killed.group_by { |result| result.mutation.operator }.filter_map do |operator, results|
          count = results.count(&:crash_kill?)
          "#{operator} #{count} of #{results.size}" if count.positive?
        end
        parts.join(", ")
      end

      def skipped_subjects(report)
        report.skipped_subjects.values.tally.each do |reason, count|
          @out.puts "skipped subjects: #{reason}: #{count}"
        end
        report.skipped_subjects.each do |subject, reason|
          @out.puts "  #{subject.id} #{relative(subject.file, report.root)}:#{subject.start_line}: #{reason}"
        end
      end

      def warnings(report)
        report.warnings.each { |warning| @out.puts "warning: #{warning}" }
      end

      def errors(report)
        errored = report.results.select { |result| result.status == :error }
        return if errored.empty?

        @out.puts "\nErrors (not counted as killed):"
        errored.first(MAX_ERRORS).each do |result|
          @out.puts "  #{result.subject.id} #{result.mutation.operator} #{result.digest}: " \
                    "#{result.reason.to_s.lines.first&.strip}"
        end
        @out.puts "  ... #{errored.size - MAX_ERRORS} more" if errored.size > MAX_ERRORS
      end

      def survivors(report)
        return if report.survivors.empty?

        @out.puts "\nSurvivors:"
        shown(report).each do |result, hidden|
          location = "#{relative(result.subject.file, report.root)}:#{result.subject.start_line}"
          @out.puts "\n#{result.subject.id} #{result.mutation.operator} #{result.digest} #{location}"
          @out.puts "ignored: #{result.ignored}" if result.ignored
          @out.puts result.diff(root: report.root)
          passing_tests(result)
          @out.puts "#{hidden} more survivor#{'s' if hidden > 1} on this line in the JSON report" if hidden.positive?
        end
      end

      # The tests that ran with the mutant applied and still passed: the
      # missing assertion belongs in one of them. They are listed likeliest
      # killers first, the order the run used. Line coverage can overstate which
      # tests exercise the line, so the list is a lead, not proof.
      def passing_tests(result)
        tests = result.covered_by
        return if tests.empty?

        @out.puts "#{tests.size} #{tests.one? ? 'test' : 'tests'} covered this line and #{passed_phrase(result)} " \
                  "(the missing check may belong in one of them):"
        tests.first(MAX_PASSING_TESTS).each { |name| @out.puts "  #{name}" }
        more = tests.size - MAX_PASSING_TESTS
        @out.puts "  ... #{more} more in the JSON report (coveredBy)" if more.positive?
      end

      # A reused verdict was not run again: its tests passed in the earlier run.
      def passed_phrase(result)
        result.reused? ? "passed in an earlier run (--incremental)" : "still passed"
      end

      # [[result, how many more on the same line]]. In review mode survivors
      # on one line usually share a fate, so one is shown: live before
      # ignored, then coarse before fine, then the earliest edit.
      def shown(report)
        return report.survivors.map { |result| [result, 0] } unless report.review?

        lines = report.survivors.group_by { |result| [result.subject.file, edit_line(result)] }
        lines.values.map do |same_line|
          best = same_line.min_by do |result|
            [result.ignored ? 1 : 0, result.mutation.coarse ? 0 : 1, result.mutation.edits.first.start_byte]
          end
          [best, same_line.size - 1]
        end
      end

      def edit_line(result)
        result.subject.line_of(result.mutation.edits.first.start_byte)
      end

      def relative(file, root)
        file.delete_prefix("#{root}/")
      end
    end
  end
end
