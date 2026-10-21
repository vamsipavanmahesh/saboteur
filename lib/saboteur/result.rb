# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "reporter/diff"
require_relative "score"

module Saboteur
  # resource_limit: the mutant's process tree hit the memory or process cap.
  # Like error it is outside the score: a mutant that eats all memory was
  # stopped by saboteur, not detected by a test.
  # ran_at_load: the mutated code only ran while the app loaded; no forked
  # test can observe a change there, so it is outside the score.
  # unreachable: a Method object captured before re-evaluation still calls
  # the original body, so no test can observe the mutant. Outside the score.
  # unverified: the --max-duration budget ran out before the verdict check
  # or timeout calibration could run, so the kill or timeout proves
  # nothing. Outside the score; the run reports budget-partial.
  STATUSES = %i[killed survived timeout resource_limit error skipped ran_at_load unreachable unverified].freeze

  # Outcome of one mutation. reason carries the skip reason, the error
  # message or the timeout limit. ignored is the ignore-list reason, if any.
  class MutantResult
    attr_reader :subject, :mutation, :status, :reason, :runtime, :killed_by, :covered_by, :mutated_source,
                :kill_cause, :executed
    attr_accessor :ignored
    # The ignore list's triage for this survivor (#155): a state from
    # IgnoreList::STATES and its reason. accepted_equivalent and wont_fix
    # suppress the exit failure (the survivor still counts in the score); a
    # todo survivor keeps counting as an unignored survivor.
    attr_accessor :triage_state, :triage_reason

    # Post-run survivor confirmation (#1063): "confirmed" once the survivor's
    # unrun covering specs had their budgeted say, "unconfirmed(reason)" when
    # they could not; nil when confirmation never applied. Additive - the
    # status keeps its meaning either way.
    attr_reader :confirmation

    def initialize(subject:, mutation:, status:, mutated_source:, reason: nil, runtime: nil, killed_by: [],
                   covered_by: [], kill_cause: nil, reused: false, rejected_kill: false, executed: nil,
                   confirmation: nil)
      raise ArgumentError, "unknown status #{status.inspect}" unless STATUSES.include?(status)

      @subject = subject
      @mutation = mutation
      @status = status
      @reason = reason
      @runtime = runtime
      @killed_by = killed_by
      @covered_by = covered_by
      @mutated_source = mutated_source
      @kill_cause = kill_cause
      @executed = executed
      @rejected_kill = rejected_kill
      @reused = reused
      @confirmation = confirmation
      @ignored = nil
      # triage_state/triage_reason stay unset until the ignore list writes
      # them: the accessors read as nil before that, and there is no
      # statement for a mutation to remove (#304 dogfood).
    end

    # The same mutant with its survivor confirmation recorded (#1063); a
    # confirmation kill flips the status and carries the confirming tests.
    # The copy is built without @ignored/triage_state, so it must run before
    # ignore marking (IgnoreList#apply) writes those.
    def with_confirmation(confirmation, status: @status, reason: @reason, runtime: @runtime,
                          killed_by: @killed_by, covered_by: @covered_by, kill_cause: @kill_cause,
                          executed: @executed)
      MutantResult.new(subject: subject, mutation: mutation, status: status, mutated_source: mutated_source,
                       reason: reason, runtime: runtime, killed_by: killed_by, covered_by: covered_by,
                       kill_cause: kill_cause, reused: reused?, rejected_kill: rejected_kill?,
                       executed: executed, confirmation: confirmation)
    end

    # The same mutant, marked unverified: the budget ran out before its
    # verdict could be checked, so it must not count as detected (#296).
    def as_unverified(reason)
      MutantResult.new(subject: subject, mutation: mutation, status: :unverified, mutated_source: mutated_source,
                       reason: reason, runtime: runtime, killed_by: killed_by, covered_by: covered_by,
                       kill_cause: kill_cause, executed: executed)
    end

    # The same mutant, marked as an error: its verdict did not hold up.
    def as_error(reason, rejected_kill: false)
      MutantResult.new(subject: subject, mutation: mutation, status: :error, mutated_source: mutated_source,
                       reason: reason, runtime: runtime, killed_by: killed_by, covered_by: covered_by,
                       executed: executed, rejected_kill: rejected_kill)
    end

    # True when every test planned for this mutant is known to have run.
    # A killed run that stopped early, a test that called exit, or a verdict
    # whose executed tests were never recorded is not complete.
    def complete?
      !executed.nil? && (covered_by - executed).empty?
    end

    def rejected_kill?
      @rejected_kill
    end

    def digest
      @digest ||= mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    end

    def survived?
      status == :survived
    end

    # Killed because a test's error, not its check, fired: NoMethodError and
    # the like. Such kills say the code broke, not that a test verified it.
    def crash_kill?
      status == :killed && !kill_cause.nil? && kill_cause != "assertion"
    end

    # Killed because a test's check failed: the test looked at a value.
    def assertion_kill?
      status == :killed && kill_cause == "assertion"
    end

    # Taken from an earlier run (--incremental) instead of run again.
    def reused?
      @reused
    end

    def unignored_survivor?
      survived? && ignored.nil?
    end

    def diff(root: nil)
      path = root ? relative(subject.file, root) : subject.file
      before, after = subject.surrounding_text
      Reporter::Diff.unified(before + subject.source + after, before + mutated_source + after,
                             path: path, first_line: subject.start_line)
    end

    private

    def relative(file, root)
      file.start_with?("#{root}/") ? file.delete_prefix("#{root}/") : file
    end
  end

  # A run that stopped before every selected subject was mutated (--fail-fast,
  # --max-duration), or whose budget ran out before every verdict check.
  # unreached lists the subject ids that never ran; truncated lists the
  # subjects that started but stopped mid-way as {subject:, omitted:}
  # entries; unverified lists the subjects whose kills the budget left
  # unchecked. The verdict covers only completed, verified work.
  EarlyStop = Data.define(:reason, :unreached, :truncated, :unverified, :planned_mutants) do
    def initialize(reason:, unreached:, truncated:, unverified:, planned_mutants: nil)
      super
    end
  end

  # Everything one run produced.
  class Report
    # More than half of the executed mutants errored: the run tested
    # almost nothing and must not pass a gate.
    MAX_ERROR_FRACTION = 0.5

    attr_reader :results, :subjects, :wall_time, :invalid_mutations, :warnings, :live_announced, :root, :seed,
                :skipped_subjects,
                :generation_events, :omissions, :run_evidence, :hazard_suppressions, :early_stop, :inline_suppressions,
                :operator_policy, :discovery_failures, :memory, :shard, :test_command, :referenced, :reuse_label

    # REVIEW: diff mode; the terminal then shows one survivor per line.
    # seed: the random seed every test run started from (nil when unknown).
    def initialize(results:, subjects:, wall_time:, root:, invalid_mutations: 0, warnings: [], live_announced: [],
                   review: false,
                   seed: nil, skipped_subjects: {}, diff_scope: nil, generation_events: [], omissions: [],
                   run_evidence: nil, hazard_suppressions: 0, early_stop: nil, matrix: false, inline_suppressions: [],
                   operator_policy: nil, discovery_failures: [], memory: nil, shard: nil,
                   test_command: nil, referenced: {}, reuse_label: nil)
      @results = results
      @subjects = subjects
      @wall_time = wall_time
      @root = root
      @invalid_mutations = invalid_mutations
      @warnings = warnings
      @live_announced = live_announced
      @review = review
      @seed = seed
      @skipped_subjects = skipped_subjects
      @diff_scope = diff_scope
      @generation_events = generation_events.dup.freeze
      @omissions = omissions.dup.freeze
      @run_evidence = run_evidence
      @hazard_suppressions = hazard_suppressions
      @early_stop = early_stop
      @matrix = matrix
      @inline_suppressions = inline_suppressions.dup.freeze
      @operator_policy = operator_policy
      @discovery_failures = discovery_failures.dup.freeze
      # Per-worker and supervisor peak RSS in MB, when the platform measured
      # it (#202); nil elsewhere, so JSON reports omit the section.
      @memory = memory.dup.freeze
      @shard = shard
      # The external command of a --test-command run, nil for in-process
      # runs. Its presence means survivors carry no coverage map (#641).
      @test_command = test_command
      # file => specs, for files whose specs were chosen by constant reference
      # or require instead of by name (zero-setup selection).
      @referenced = referenced
      @reuse_label = reuse_label
    end

    # A --matrix run: every covering test ran per mutant.
    def matrix?
      @matrix
    end

    # True when the run was scoped to a diff (--since): the expand command
    # echoes that scope.
    def diff?
      !@diff_scope.nil?
    end

    # In diff mode, the changed lines (sorted) that a mutant touches; empty
    # outside diff mode, or when the mutant touches none (a whole-body mutant
    # of a method whose only change is its signature).
    def changed_lines_for(result)
      @diff_scope ? @diff_scope.changed_lines_for(result.subject, result.mutation) : []
    end

    def changed_line_distance(result)
      @diff_scope&.distance_for(result.subject, result.mutation)
    end

    def rejected_kills
      results.count(&:rejected_kill?)
    end

    # Errored mutants (a crash, a neutral check that failed) are outside
    # the score, so a run whose executed mutants mostly errored tested
    # almost nothing. Skipped mutants never ran: they are neither the
    # numerator nor the denominator.
    def majority_errored?
      return false if executed.empty?

      executed.count { |result| result.status == :error }.fdiv(executed.size) > MAX_ERROR_FRACTION
    end

    def review?
      @review
    end

    def counts
      STATUSES.to_h { |status| [status, results.count { |result| result.status == status }] }
    end

    # (killed + timeout) / (killed + survived + timeout); nil with nothing tested.
    def score
      score_breakdown.value
    end

    # The score with its split into assertion kills and crash kills.
    def score_breakdown
      @score_breakdown ||= Score.of(results)
    end

    # The same breakdown without the whole-body mutants (every
    # mutation marked coarse: body_nil, body_true, body_false, body_raise). Almost any test that runs the method kills
    # those, so they flatter the score.
    def fine_score_breakdown
      @fine_score_breakdown ||= Score.of(results.reject { |result| result.mutation.coarse })
    end

    def coarse_score_breakdown
      @coarse_score_breakdown ||= Score.of(results.select { |result| result.mutation.coarse })
    end

    def survivors
      results.select(&:survived?)
    end

    def unignored_survivors
      results.select(&:unignored_survivor?)
    end

    def skip_reasons
      results.select { |result| result.status == :skipped }.group_by(&:reason).transform_values(&:size)
    end

    def executed
      results.reject { |result| result.status == :skipped }
    end

    def mean_runtime
      timed = executed.reject(&:reused?).filter_map(&:runtime)
      timed.empty? ? nil : timed.sum / timed.size
    end
  end
end
