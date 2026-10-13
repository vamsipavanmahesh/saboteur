# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "next_steps"
require_relative "survivor_ranking"
require_relative "palette"
require_relative "score_table"
require_relative "survivor_list"
require_relative "test_matrix"

module Saboteur
  module Reporter
    # Plain-text report: survivors first (grouped by file, method and line),
    # then errors and notes, then a short summary last so it stays on screen.
    # Debug statistics (score split, timings, kill causes) need verbose.
    class Terminal
      MAX_ERRORS = 10
      MAX_PASSING_TESTS = SurvivorList::MAX_PASSING_TESTS

      def initialize(out, verbose: false, color: :auto)
        @out = out
        @verbose = verbose
        @palette = Palette.for(out, mode: color)
        @score_table = ScoreTable.new(out, @palette)
        @next_steps = NextSteps.new(out, @palette)
      end

      def call(report)
        survivors(report)
        errors(report)
        skipped_subjects(report)
        outside_the_score(report)
        inline_suppressions(report)
        warnings(report)
        early_stop(report)
        test_matrix(report)
        summary(report)
      end

      private

      def test_matrix(report)
        return unless report.matrix?

        matrix = TestMatrix.new(report.results)
        @out.puts "test matrix: #{matrix.tests.size} tests ran against mutants"
        incomplete_matrix_note(matrix)
        matrix_list("blind (covered mutants, killed none)", matrix.blind) do |test|
          "#{matrix.mutants_covered(test)} covered"
        end
        matrix_list("redundant (every kill had another killer)", matrix.redundant) do |test|
          "#{matrix.mutants_killed(test)} kills"
        end
      end

      def incomplete_matrix_note(matrix)
        return if matrix.incomplete.zero?

        @out.puts "  #{matrix.incomplete} mutants stopped before every covering test ran (incomplete): " \
                  "their tests get no blind or redundant verdict"
      end

      def matrix_list(title, tests)
        @out.puts "  #{title}: #{tests.size}"
        tests.first(TestMatrix::MAX_LISTED).each { |test| @out.puts "    #{test}  #{yield(test)}" }
        more = tests.size - TestMatrix::MAX_LISTED
        @out.puts "    ... #{more} more" if more.positive?
      end

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
        @score_table.call(report)
        @out.puts @score_table.legend
        @next_steps.call(report)
      end

      def status_line(report)
        c = report.counts
        survived = "survived #{c[:survived]}"
        ignored = report.survivors.size - report.unignored_survivors.size
        survived += " (#{ignored} ignored)" if ignored.positive?
        line = "#{@palette.paint(:green,
                                 "killed #{c[:killed]}")}  #{@palette.paint(:red,
                                                                            survived)}  timeout #{c[:timeout]}  " \
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
        @out.puts "score #{percent(breakdown.value)}" \
                  "#{if @verbose
                       "#{score_split(breakdown)} (killed+timeout)/(killed+survived+timeout); " \
                         'errors, resource limits and skips excluded'
                     end}"
        report.skip_reasons.each { |reason, count| @out.puts "skipped: #{reason}: #{count}" }
        reused = report.results.count(&:reused?)
        @out.puts "reused #{reused} of #{report.results.size} verdicts from earlier runs (--incremental)" if
          reused.positive?
        @out.puts "invalid mutations dropped (did not parse): #{report.invalid_mutations}" if
          report.invalid_mutations.positive?
        hazard_suppressions(report)
        debug_details(report) if @verbose
      end

      def debug_details(report)
        whole_body_score(report)
        mean = report.mean_runtime
        @out.puts "mean time per executed mutant #{format('%.3f', mean)} s" if mean
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

      # The verdict covers only the subjects that ran, so say it where the
      # score is read.
      def early_stop(report)
        stop = report.early_stop
        return unless stop

        @out.puts @palette.paint(:yellow, "stopped early (--fail-fast): #{stop.unreached.size} selected " \
                                          "subject#{'s' unless stop.unreached.one?} did not run; the score below " \
                                          "covers only the subjects that ran")
        stop.unreached.first(MAX_ERRORS).each { |id| @out.puts "  not run: #{id}" }
        @out.puts "  ... #{stop.unreached.size - MAX_ERRORS} more" if stop.unreached.size > MAX_ERRORS
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
        SurvivorList.new(@out, @palette).call(report, ranked_survivors(report))
        @out.puts unless report.survivors.empty?
      end

      # Live survivors precede accepted ones; each group follows SurvivorRanking.
      def ranked_survivors(report)
        live, accepted = report.survivors.partition(&:unignored_survivor?)
        [live, accepted].flat_map { |group| SurvivorRanking.ordered(report, group) }
      end

      def relative(file, root)
        file.delete_prefix("#{root}/")
      end
    end
  end
end
