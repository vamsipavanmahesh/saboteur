# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Plain-text summary: counts per status, score, timings, skip reasons,
    # errors, then a unified diff for each survivor.
    class Terminal
      MAX_ERRORS = 10
      MAX_PASSING_TESTS = 5
      MAX_CHANGED_LINES = 3

      def initialize(out)
        @out = out
      end

      def call(report)
        summary(report)
        skipped_subjects(report)
        outside_the_score(report)
        inline_suppressions(report)
        warnings(report)
        errors(report)
        survivors(report)
      end

      private

      def inline_suppressions(report)
        return if report.inline_suppressions.empty?

        @out.puts("Inline suppressions: #{report.inline_suppressions.size} (outside the score)")
        report.inline_suppressions.each do |entry|
          path = entry[:file].delete_prefix("#{report.root}/")
          @out.puts("  #{path}:#{entry[:line]} #{entry[:subject]} #{entry[:operator]} " \
                    "#{entry[:digest]}: #{entry[:reason]}")
        end
      end

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
        line = "killed #{c[:killed]}  #{survived}  timeout #{c[:timeout]}  " \
               "resource limit #{c[:resource_limit]}  error #{c[:error]}  skipped #{c[:skipped]}"
        line += "  ran at load #{c[:ran_at_load]}" if c[:ran_at_load].positive?
        line += "  unreachable #{c[:unreachable]}" if c[:unreachable].positive?
        line
      end

      def hazard_suppressions(report)
        return unless report.hazard_suppressions.positive?

        @out.puts "hazardous mutations suppressed: #{report.hazard_suppressions} " \
                  "(--allow-hazardous runs them anyway; the canary still watches the tree)"
      end

      def details(report)
        breakdown = report.score_breakdown
        @out.puts "score #{percent(breakdown.value)}#{score_split(breakdown)} " \
                  "(killed+timeout)/(killed+survived+timeout); errors, resource limits and skips excluded"
        whole_body_score(report)
        mean = report.mean_runtime
        @out.puts "mean time per executed mutant #{format('%.3f', mean)} s" if mean
        @out.puts "invalid mutations dropped (did not parse): #{report.invalid_mutations}" if
          report.invalid_mutations.positive?
        hazard_suppressions(report)
        report.skip_reasons.each { |reason, count| @out.puts "skipped: #{reason}: #{count}" }
        reused = report.results.count(&:reused?)
        @out.puts "reused #{reused} of #{report.results.size} verdicts from earlier runs (--incremental)" if
          reused.positive?
        @out.puts "kills rejected by unchanged-method check: #{report.rejected_kills}"
        kill_causes(report)
      end

      # " (assertion 50.0 %, crash 50.0 %)": how much of the score is a failed
      # check and how much is a crash. Timeouts and kills with no recorded
      # cause are named only when there are some, so the parts add up.
      def score_split(breakdown)
        return "" unless breakdown.split_known?

        " (#{breakdown.parts.map { |label, share| "#{label} #{percent(share)}" }.join(', ')})"
      end

      # Whole-body mutants (body_nil, body_true, body_false, body_raise) are
      # killed by almost any test that runs the method, so they get their own
      # line.
      def whole_body_score(report)
        whole = report.coarse_score_breakdown
        fine = report.fine_score_breakdown
        return if whole.tested.zero? || fine.tested.zero?

        @out.puts "score without whole-body mutants #{percent(fine.value)}#{score_split(fine)} " \
                  "(#{fine.tested} mutants); whole-body mutants alone #{percent(whole.value)} (#{whole.tested})"
      end

      def percent(share)
        share ? format("%.1f %%", share * 100) : "n/a"
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

      # Mutants no test can judge, listed apart so they are not read as
      # misses: code that only ran while the app loaded, and methods a
      # captured Method object still calls in their original form.
      def outside_the_score(report)
        { ran_at_load: "Ran at load (out of the score):",
          unreachable: "Unreachable (out of the score):" }.each do |status, heading|
          results = report.results.select { |result| result.status == status }
          next if results.empty?

          @out.puts heading
          results.each do |result|
            location = "#{relative(result.subject.file, report.root)}:#{result.subject.start_line}"
            @out.puts "  #{result.subject.id} #{result.mutation.operator} #{result.digest} #{location}"
          end
          @out.puts "  hint: #{results.first.reason}" if results.first.reason
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
          changed_lines(report, result)
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

      # In diff mode: the changed lines this mutant touches. The location above
      # is where the mutated statement starts, which can be a line or two above
      # the line that changed.
      def changed_lines(report, result)
        lines = report.changed_lines_for(result)
        return if lines.empty?

        path = relative(result.subject.file, report.root)
        shown = lines.first(MAX_CHANGED_LINES).map { |line| "#{path}:#{line}" }.join(", ")
        more = lines.size - MAX_CHANGED_LINES
        @out.puts "changed #{lines.one? ? 'line' : 'lines'}: #{shown}#{" (+#{more} more)" if more.positive?}"
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
