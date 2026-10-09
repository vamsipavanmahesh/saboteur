# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "reporter/diff"

module Saboteur
  STATUSES = %i[killed survived timeout error skipped].freeze

  # Outcome of one mutation. reason carries the skip reason, the error
  # message or the timeout limit. ignored is the ignore-list reason, if any.
  class MutantResult
    attr_reader :subject, :mutation, :status, :reason, :runtime, :killed_by, :covered_by, :mutated_source,
                :kill_cause
    attr_accessor :ignored

    def initialize(subject:, mutation:, status:, mutated_source:, reason: nil, runtime: nil, killed_by: [],
                   covered_by: [], kill_cause: nil)
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
      @ignored = nil
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
    attr_reader :results, :subjects, :wall_time, :invalid_mutations, :warnings, :root

    # REVIEW: diff mode; the terminal then shows one survivor per line.
    def initialize(results:, subjects:, wall_time:, root:, invalid_mutations: 0, warnings: [], review: false)
      @results = results
      @subjects = subjects
      @wall_time = wall_time
      @root = root
      @invalid_mutations = invalid_mutations
      @warnings = warnings
      @review = review
    end

    def review?
      @review
    end

    def counts
      STATUSES.to_h { |status| [status, results.count { |result| result.status == status }] }
    end

    # (killed + timeout) / (killed + survived + timeout); nil with nothing tested.
    def score
      c = counts
      detected = c[:killed] + c[:timeout]
      tested = detected + c[:survived]
      tested.zero? ? nil : detected.fdiv(tested)
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
      timed = executed.filter_map(&:runtime)
      timed.empty? ? nil : timed.sum / timed.size
    end
  end
end
