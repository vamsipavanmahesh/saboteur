# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "safe_out"
require_relative "wording"
require_relative "baseline_tail"
require_relative "next_steps"
require_relative "kill_causes"
require_relative "survivor_ranking"
require_relative "palette"
require_relative "notice"
require_relative "score_table"
require_relative "survivor_list"
require_relative "survivor_classification"
require_relative "test_matrix"
require_relative "reuse_note"

module Saboteur
  module Reporter
    # Plain-text report: survivors first (grouped by file, method and line),
    # then errors and notes, then a short summary last so it stays on screen.
    # Debug statistics (score split, timings, kill causes) need verbose.
    class Terminal
      MAX_ERRORS = 10
      MAX_NOT_SCORED = 10
      MAX_PASSING_TESTS = 5

      def initialize(out, verbose: false, quiet: false, color: :auto, overrides: nil,
                     replay_command: nil, all_mutants: false, exit_code: nil,
                     threshold: nil, previous_score: nil, baseline_gate: nil,
                     scope: "whole project", baseline: nil, coverage: nil, mutant_phase: nil)
        @out = SafeOut.new(out)
        @all_mutants = all_mutants
        @verbose = verbose
        @quiet = quiet
        # Clean-screen context: scope from the CLI; PR4a plumbs the phase stats.
        @scope = scope
        @baseline = baseline
        @coverage = coverage
        @mutant_phase = mutant_phase
        @palette = Palette.for(out, mode: color, overrides: overrides)
        @score_table = ScoreTable.new(@out, @palette)
        @next_steps = NextSteps.new(@out, @palette, replay_command: replay_command)
        # The CLI classifies the run: the closing verdict line names the
        # exit and its reason; the threshold gives the score its colour.
        @exit_code = exit_code
        @threshold = threshold
        # Last recorded score from the score history, for the headline delta.
        @previous_score = previous_score
        # The --baseline run gate, when the run was gated: its comparison
        # replaces the canonical tally and owns the exit-1 verdict.
        @baseline_gate = baseline_gate
      end

      def call(report)
        return quiet_call(report) if @quiet

        survivors(report)
        errors(report)
        skipped_subjects(report) if @verbose
        test_command_gaps(report)
        outside_the_score(report)
        inline_suppressions(report)
        warnings(report)
        early_stop(report)
        test_matrix(report)
        operator_policy(report)
        summary(report)
      end

      private

      def middot = @palette.glyph(:middot)

      # One finding per statement, live survivors in ranked order (#1065).
      def quiet_call(report)
        groups = SurvivorRanking.ordered(report, report.unignored_survivors).group_by do |result|
          [relative(result.subject.file, report.root), MutationText.line(result), result.subject.id]
        end
        @out.puts(groups.map { |(path, line, id), rs| quiet_survivor_line(path, line, id, rs) }) if groups.any?
        untested_subjects(report).each do |subject|
          @out.puts "#{relative(subject.file, report.root)}:#{subject.start_line} #{subject.id} [untested]"
        end
        @baseline_gate ? BaselineTail.new(@out, @palette).call(@baseline_gate, @exit_code) : canonical_line(report)
        verdict_line(report)
      end

      def quiet_survivor_line(path, line, subject_id, results)
        first, *rest = results
        label = SurvivorClassification.label(first)
        text = "#{path}:#{line} #{subject_id}#{" [#{label}]" if label} - #{first.digest}"
        rest.any? ? "#{text} (+#{rest.size} more)" : text
      end

      def operator_policy(report)
        policy = report.operator_policy
        return unless policy && policy["excluded"].any?

        @out.puts("Excluded operators: #{policy['excluded'].join(', ')} " \
                  "(policy #{policy['version']}; #{policy['effective'].size} enabled)")
      end

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

      # An early stop runs fewer mutants than the selection: say both
      # numbers so "4 mutants" is not read as the whole plan (#582).
      def mutant_counts(report)
        planned = report.early_stop&.planned_mutants
        return Text.counted(report.results.size, "mutant") unless planned && planned > report.results.size

        "#{Text.counted(planned, 'mutant')} selected, #{report.results.size} attempted"
      end

      def summary(report)
        # A gated run's clean screen is PR8's baseline tail, not this one.
        return clean_screen(report) if !@baseline_gate && clean_run?(report)

        seed = report.seed && ", seed #{report.seed} (repeat with --seed #{report.seed})"
        tally = "saboteur #{VERSION}: #{Text.counted(report.subjects.size, 'subject')}, #{mutant_counts(report)}, " \
                "wall #{format('%.2f', report.wall_time)} s#{seed}"
        @out.puts @palette.paint(:dim, tally)
        @out.puts report.shard.line if report.shard
        score_headline(report)
        details(report)
        @score_table.call(report)
        not_scored(report)
        @baseline_gate ? BaselineTail.new(@out, @palette).call(@baseline_gate, @exit_code) : canonical_line(report)
        verdict_line(report)
        @next_steps.call(report)
      end

      # The deliberate success screen (PR6): a fully-killed run says the win
      # out loud. Replaces the whole closing block on a clean run.
      def clean_run?(report)
        counts = report.counts
        @exit_code&.zero? && report.executed.any? && report.unignored_survivors.empty? && !report.early_stop &&
          (counts[:error] + counts[:timeout] + counts[:unverified] + counts[:resource_limit]).zero?
      end

      def clean_screen(report)
        header = "saboteur #{VERSION} #{middot} #{@scope}"
        header += " #{middot} seed #{report.seed}" if report.seed
        @out.puts @palette.paint(:dim, header)
        clean_phases(report)
        @out.puts
        win = "#{@palette.glyph(:check)} #{win_tally(report)} #{middot} " \
              "score #{format('%.1f%%', report.score * 100)}"
        total = @palette.paint(:dim, "#{middot} #{format('%.1f', report.wall_time)}s total")
        @out.puts "#{@palette.paint(:pass, win)} #{total}"
        untested = untested_subjects(report)
        @out.puts "  #{@palette.paint(:warn, Wording.untested_win_note(untested))}" if untested.any?
        ReuseNote.new(@out).print(report)
        # The footer owns the report paths (#1187); the clean screen's own
        # hint is the follow-up run a whole-project win suggests.
        @out.puts "  #{@palette.paint(:dim, 'next: saboteur run --since origin/main')}" if @scope == "whole project"
      end

      # The phase lines and the progress-dots line print only when their data
      # is present: PR4a plumbs baseline/coverage/phase stats, PR5 owns the
      # live dots this echoes.
      def clean_phases(report)
        return unless @baseline && @coverage && @mutant_phase

        check = @palette.paint(:pass, @palette.glyph(:check))
        @out.puts "#{check} baseline green (#{@baseline[:examples]} examples, #{@baseline[:seconds]}s)  " \
                  "#{check} coverage map: #{@coverage[:tests]} tests (#{@coverage[:seconds]}s)"
        total = report.executed.size
        dots = "." * total
        suffix = @palette.paint(:dim, "(#{total}/#{total} #{middot} #{@mutant_phase[:seconds]}s)")
        @out.puts "#{dots}  #{suffix}"
      end

      def win_tally(report)
        "#{report.counts[:killed]}/#{report.executed.size} mutants killed"
      end

      def hazard_suppressions(report)
        return unless report.hazard_suppressions.positive?

        @out.puts "hazardous mutations suppressed: #{report.hazard_suppressions} " \
                  "(--allow-hazardous runs them anyway; the canary still watches the tree)"
      end

      # Subjects skipped for "no coverage" (CandidateSelection's reason).
      def untested_subjects(report)
        report.skipped_subjects.select { |_, reason| reason == ScoreTable::NO_COVERAGE }
              .keys.sort_by { |subject| [subject.file, subject.start_line] }
      end

      # The score covers tested subjects only; the untested count stands
      # next to it, never folded in.
      def score_headline(report)
        breakdown = report.score_breakdown
        untested = untested_subjects(report)
        # The share covers scored mutants only, so an error-dominated run
        # must not print it as a bare score: "100.0 %" above "the run
        # tested almost nothing" reads as a contradiction (#557).
        if report.majority_errored?
          @out.puts "Score: n/a (#{breakdown.tested} of #{report.executed.size} mutants scored, " \
                    "#{percent(breakdown.value)} of scored)"
          return
        end

        line = "Score: #{painted_score(breakdown.value)}#{headline_context(breakdown.value)}"
        line << score_parenthetical(breakdown)
        if @verbose && breakdown.tested.positive?
          line << "#{score_split(breakdown)} (killed+timeout)/(killed+survived+timeout); " \
                  "errors, resource limits and skips excluded"
        end
        if untested.any?
          line << "  #{@palette.paint(:warn, "#{untested.size} subject#{'s' unless untested.one?} " \
                                             "not scored - #{Wording.no_execution(untested.size)}")}"
        end
        @out.puts line
      end

      # The share of tested mutants the run detected: "killed" alone would
      # count timeouts too, so Wording names both when one is in the number.
      def score_parenthetical(breakdown)
        return " - nothing tested" if breakdown.tested.zero?

        " (#{breakdown.detected}/#{breakdown.tested} #{Wording.detected_word(breakdown)}, tested subjects)"
      end

      # What the score is judged against and where it came from: the
      # threshold it must meet, and the last score the history recorded.
      def headline_context(value)
        text = +""
        text << threshold_echo(value) if @threshold
        text << @palette.paint(:dim, " #{middot} prev #{format('%.1f%%', @previous_score * 100)}") if @previous_score
        text
      end

      # The headline echoes the threshold it is judged against; a score
      # below it is a break, painted with the fail colour.
      def threshold_echo(value)
        broken = value && value * 100 < @threshold
        text = " #{middot} threshold #{format('%g', @threshold)}#{' (break)' if broken}"
        broken ? @palette.paint(:fail, text) : @palette.paint(:dim, text)
      end

      # No threshold, no colour. A single --threshold T is the band (T, T):
      # red below, green at or above, no yellow state.
      def painted_score(value)
        text = value ? format("%.1f%%", value * 100) : "n/a"
        return text unless @threshold && value

        @palette.paint(band_color(value * 100, @threshold, @threshold), text)
      end

      # Stryker band: red below low, green at or above high, yellow inside.
      # A single --threshold T passes (T, T), so yellow is unreachable there.
      def band_color(score, low, high)
        return :fail if score < low
        return :pass if score >= high

        :warn
      end

      # The gaps the score cannot see, named with their location.
      def not_scored(report)
        untested = untested_subjects(report)
        return if untested.empty?

        @out.puts
        @out.puts @palette.paint(:warn, "Not scored - no test executes these (treat these as your biggest gaps):")
        entries = untested.map { |subject| "#{subject.id} (#{subject.location(report.root)})" }
        line = "  #{@palette.paint(:warn, '!')} #{entries.first(MAX_NOT_SCORED).join(" #{middot} ")}"
        line << " #{middot} ... #{entries.size - MAX_NOT_SCORED} more" if entries.size > MAX_NOT_SCORED
        @out.puts line
      end

      # One greppable line, pytest-style.
      def canonical_line(report)
        parts = state_parts(report)
        parts << "no mutants" if parts.empty?
        line = "saboteur: #{parts.join(', ')} in #{duration(report.wall_time)}"
        line += " - score #{painted_score(report.score)}"
        line += " (threshold #{format('%g', @threshold)})" if @threshold
        @out.puts line
      end

      # The states that say how the run went: nonzero counts only, except
      # the untested count, which is always named when there is any.
      def state_parts(report)
        counts = report.counts
        live = report.unignored_survivors.size
        untested = untested_subjects(report).size
        [counted(counts[:killed], "killed", plural: false, color: :pass),
         counted(live, "survived", plural: false, color: :fail),
         counted(report.survivors.size - live, "accepted", plural: false),
         counted(counts[:timeout], "timeout", color: :warn), counted(counts[:resource_limit], "resource limit"),
         error_part(report, counts[:error]), counted(counts[:unverified], "unverified", plural: false),
         ("#{untested} subject#{'s' unless untested == 1} untested" if untested.positive?)].compact
      end

      def counted(count, word, plural: true, color: nil)
        return unless count.positive?

        text = "#{count} #{word}#{'s' if plural && count != 1}"
        color ? @palette.paint(color, text) : text
      end

      def error_part(report, errors)
        return if errors.zero?

        rejected = report.rejected_kills
        note = " (#{rejected} rejected kill#{'s' if rejected > 1})" if rejected.positive?
        "#{errors} error#{'s' unless errors == 1}#{note}"
      end

      def duration(seconds)
        minutes, rest = seconds.round.divmod(60)
        minutes.positive? ? "#{minutes}m#{rest.to_s.rjust(2, '0')}s" : "#{rest}s"
      end

      # Why the run exits the way it does, echoing the thresholds. Exit 0
      # prints no verdict: PR6 owns the clean screen.
      # The exit codes are the CLI's (CLI::EXIT_*): literals here, because
      # the CLI requires this file, not the other way round.
      def verdict_line(report)
        return if @exit_code.nil? || @exit_code.zero?
        return if @baseline_gate && @exit_code == 1 # BaselineTail renders the gate's verdict

        case @exit_code
        when 1 then @out.puts @palette.paint(:fail, failure_verdict(report))
        when 4
          @out.puts @palette.paint(:fail, "#{@palette.glyph(:cross)} exit 4 - --max-duration budget spent; " \
                                          "the score covers only completed work")
        else
          @out.puts @palette.paint(:fail, incomplete_verdict(report))
        end
      end

      def failure_verdict(report)
        reasons = []
        score = report.score
        if @threshold && score && score * 100 < @threshold
          reasons << "score #{format('%.1f%%', score * 100)} below threshold #{format('%g', @threshold)}"
        end
        live = report.unignored_survivors.size
        reasons << "#{live} survivor#{'s' unless live == 1}" if live.positive?
        reasons << "gate limits exceeded" if reasons.empty?
        "#{@palette.glyph(:cross)} exit 1 - #{reasons.join(', ')}"
      end

      def incomplete_verdict(report)
        if report.majority_errored?
          "#{@palette.glyph(:cross)} exit 3 - most executed mutants errored; the run tested almost nothing"
        elsif unverifiable_change?(report)
          count = report.subjects.size
          reasons = report.skipped_subjects.values.uniq.join(", ")
          "#{@palette.glyph(:cross)} exit 3 - #{count} change#{'s' unless count == 1} could not be " \
            "verified (#{reasons})"
        elsif report.executed.any? && report.executed.all? { |result| result.status == :unreachable }
          "#{@palette.glyph(:cross)} exit 3 - the change could not be verified (all mutants unreachable)"
        elsif report.early_stop && report.score_breakdown.tested.zero?
          "#{@palette.glyph(:cross)} exit 3 - stopped before any mutant was tested; there is no score to judge"
        else
          "#{@palette.glyph(:cross)} exit 3 - run incomplete; the score is not a verified result"
        end
      end

      # A scoped run whose every subject was skipped verified nothing (#574).
      def unverifiable_change?(report)
        report.review? && report.subjects.any? &&
          report.subjects.all? { |subject| report.skipped_subjects.key?(subject) }
      end

      def details(report)
        report.skip_reasons.each { |reason, count| @out.puts skip_reason_line(reason, count) } if @verbose
        ReuseNote.new(@out).print(report)
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
        KillCauses.new(@out).print(report)
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

      # #641: a --test-command run has no coverage map, so a subject the
      # command never loads reads as ordinary survivors. When a subject's
      # mutants all came back without a single kill or error and at least
      # one survivor, say the command may not exercise it - a heuristic
      # line, never a score or exit-code change.
      def test_command_gaps(report)
        return unless report.test_command

        report.results.group_by(&:subject).each do |subject, results|
          next if results.any? { |result| %i[killed timeout].include?(result.status) }
          next if results.any? { |result| result.status == :error }
          next unless results.any?(&:survived?)

          file = relative(subject.file, report.root)
          @out.puts "#{subject.id}: no coverage map under --test-command; check your command exercises #{file}"
        end
      end

      # "no coverage" names two different things (#1070): subjects no test
      # runs at all, and mutant locations inside covered methods that no
      # test reaches. Say which is which; every other reason prints as-is.
      def skip_reason_line(reason, count)
        reason == "no coverage" ? "mutant locations not reached: #{count}" : "skipped: #{reason}: #{count}"
      end

      def skipped_subject_line(reason, count)
        reason == "no coverage" ? "methods never run by tests: #{count}" : "skipped subjects: #{reason}: #{count}"
      end

      # Verbose-only: the Not scored block names the no-coverage subjects;
      # other skips are announced live in a scoped run (#574).
      def skipped_subjects(report)
        report.skipped_subjects.values.tally.each { |reason, count| @out.puts skipped_subject_line(reason, count) }
        report.skipped_subjects.each do |subject, reason|
          next if reason == ScoreTable::NO_COVERAGE

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

      # The verdict covers only the completed work, so say it where the
      # score is read.
      def early_stop(report)
        stop = report.early_stop
        return unless stop

        label = stop.reason == "fail_fast" ? "--fail-fast" : "--max-duration spent"
        @out.puts @palette.paint(:warn, "stopped early (#{label}): #{early_stop_summary(stop)}; the score below " \
                                        "covers only completed work")
        budget_shortfall(stop, report.results.size)
        list(stop.unreached) { |id| "  not run: #{id}" }
        list(stop.truncated) { |entry| "  stopped mid-way: #{entry[:subject]} (#{entry[:omitted]} mutants omitted)" }
        list(stop.unverified) { |id| "  unverified: #{id}" }
      end

      def list(entries)
        entries.first(MAX_ERRORS).each { |entry| @out.puts yield(entry) }
        @out.puts "  ... #{entries.size - MAX_ERRORS} more" if entries.size > MAX_ERRORS
      end

      def budget_shortfall(stop, completed)
        return unless stop.reason == "max_duration"

        # Exit 4 alone does not say whether anything was judged: headline
        # it when the baselines and coverage map ate the whole budget (#637).
        if completed.zero?
          @out.puts @palette.paint(:warn, "no mutants ran before the --max-duration budget was spent; " \
                                          "there is no score to judge")
        end
        line = if stop.planned_mutants
                 "partial: #{stop.planned_mutants - completed} of #{stop.planned_mutants} mutants not run"
               else
                 "partial: mutant count unknown; the budget was spent before planning finished"
               end
        @out.puts @palette.paint(:warn, line)
      end

      def early_stop_summary(stop)
        parts = []
        if stop.unreached.any?
          parts << "#{stop.unreached.size} selected subject#{'s' unless stop.unreached.one?} did not run"
        end
        if stop.truncated.any?
          omitted = stop.truncated.sum { |entry| entry[:omitted] }
          parts << "#{stop.truncated.size} subject#{'s' unless stop.truncated.one?} stopped mid-way " \
                   "(#{omitted} mutants omitted)"
        end
        if stop.unverified.any?
          parts << "#{stop.unverified.size} subject#{'s' unless stop.unverified.one?} left with unverified results"
        end
        parts.join("; ")
      end

      # Live-announced warnings already printed when they were announced
      # (#605): they stay in report.warnings for JSON/HTML/agent consumers
      # but are not printed a second time here.
      def warnings(report)
        report.warnings.each do |warning|
          @out.puts Notice.paint(@palette, "warning: #{warning}") unless report.live_announced.include?(warning)
        end
      end

      def errors(report)
        # Rejected kills are verdicts, not tool errors: the tests failed,
        # but they also fail with the method unchanged (#375).
        rejected, errored = report.results.select { |result| result.status == :error }.partition(&:rejected_kill?)
        unless rejected.empty?
          @out.puts "\nRejected kills (tests also fail with the method unchanged; not counted as killed):"
          print_error_lines(rejected)
        end
        return if errored.empty?

        @out.puts "\nErrors (not counted as killed):"
        print_error_lines(errored)
      end

      def print_error_lines(errored)
        errored.first(MAX_ERRORS).each do |result|
          lines = result.reason.to_s.lines.map(&:strip)
          @out.puts "  #{result.subject.id} #{result.mutation.operator} #{result.digest}: #{lines.first}"
          lines.drop(1).each { |line| @out.puts "    #{line}" }
        end
        @out.puts "  ... #{errored.size - MAX_ERRORS} more" if errored.size > MAX_ERRORS
      end

      def survivors(report)
        SurvivorList.new(@out, @palette, all_mutants: @all_mutants).call(report, ranked_survivors(report))
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
