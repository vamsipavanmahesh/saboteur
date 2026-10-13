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
  STATUSES = %i[killed survived timeout resource_limit error skipped ran_at_load unreachable].freeze

  # Outcome of one mutation. reason carries the skip reason, the error
  # message or the timeout limit. ignored is the ignore-list reason, if any.
  class MutantResult
    attr_reader :subject, :mutation, :status, :reason, :runtime, :killed_by, :covered_by, :mutated_source,
                :kill_cause
    attr_accessor :ignored

    def initialize(subject:, mutation:, status:, mutated_source:, reason: nil, runtime: nil, killed_by: [],
                   covered_by: [], kill_cause: nil, reused: false, rejected_kill: false)
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
      @rejected_kill = rejected_kill
      @reused = reused
      @ignored = nil
    end

    # The same mutant, marked as an error: its verdict did not hold up.
    def as_error(reason, rejected_kill: false)
      MutantResult.new(subject: subject, mutation: mutation, status: :error, mutated_source: mutated_source,
                       reason: reason, runtime: runtime, killed_by: killed_by, covered_by: covered_by,
                       rejected_kill: rejected_kill)
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

  # Everything one run produced.
  class Report
    # More than half of the executed mutants errored: the run tested
    # almost nothing and must not pass a gate.
    MAX_ERROR_FRACTION = 0.5

    attr_reader :results, :subjects, :wall_time, :invalid_mutations, :warnings, :root, :seed, :skipped_subjects,
                :generation_events, :omissions, :run_evidence

    # REVIEW: diff mode; the terminal then shows one survivor per line.
    # seed: the random seed every test run started from (nil when unknown).
    def initialize(results:, subjects:, wall_time:, root:, invalid_mutations: 0, warnings: [], review: false,
                   seed: nil, skipped_subjects: {}, diff_scope: nil, generation_events: [], omissions: [],
                   run_evidence: nil)
      @results = results
      @subjects = subjects
      @wall_time = wall_time
      @root = root
      @invalid_mutations = invalid_mutations
      @warnings = warnings
      @review = review
      @seed = seed
      @skipped_subjects = skipped_subjects
      @diff_scope = diff_scope
      @generation_events = generation_events.dup.freeze
      @omissions = omissions.dup.freeze
      @run_evidence = run_evidence
    end

    # In diff mode, the changed lines (sorted) that a mutant touches; empty
    # outside diff mode, or when the mutant touches none (a whole-body mutant
    # of a method whose only change is its signature).
    def changed_lines_for(result)
      @diff_scope ? @diff_scope.changed_lines_for(result.subject, result.mutation) : []
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
