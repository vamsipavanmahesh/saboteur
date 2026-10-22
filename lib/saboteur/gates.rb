# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # CI gates on how many mutants ended as a timeout or an error. A limit is a
  # count ("3") or a percentage of the executed mutants ("5%"); the gate fails
  # only when the count is above it. Unset means no gate.
  class Gates
    Violation = Data.define(:cause, :message)

    # config key => [mutant status, exit cause recorded in the JSON report, flag]
    SETTINGS = {
      "max_timeouts" => [:timeout, "maxTimeouts", "--max-timeouts"],
      "max_errors" => [:error, "maxErrors", "--max-errors"]
    }.freeze
    LIMIT = /\A(\d+)(%?)\z/

    # The normalized limit: nil, an Integer count, or a String ending in "%".
    # A malformed value is a ConfigError that names the setting.
    def self.limit(value, key)
      return nil if value.nil?

      match = LIMIT.match(value.to_s.strip)
      raise ConfigError, "#{key} must be a count (3) or a percentage (5%), got #{value.inspect}" unless match

      digits, suffix = match.captures
      number = digits.to_i
      raise ConfigError, "#{key} percentage must be at most 100" if suffix == "%" && number > 100

      suffix.empty? ? number : "#{number}%"
    end

    # The --max-timeouts and --max-errors flags; each value goes to the block with its config key.
    def self.define_options(parser)
      SETTINGS.each do |key, (status, _cause, flag)|
        parser.on("#{flag} N", "Exit 1 when more than N mutants end as #{status} (N or N%)") do |value|
          yield key.to_sym, value
        end
      end
    end

    def initialize(config)
      @limits = SETTINGS.keys.to_h { |key| [key, self.class.limit(config[key], key)] }
      @score_gates = Array(config["score_gates"])
    end

    attr_reader :cause

    def any?
      @limits.values.any? || @score_gates.any?
    end

    # The flag-style name of the configured gate, for the --agent rejection.
    def agent_option_name
      @score_gates.any? ? "score gates" : "--max-* gates"
    end

    # --max-errors judges errored mutants, so a threshold run tolerates them.
    def judges_errors?
      !@limits.fetch("max_errors").nil?
    end

    # Prints the gate notes and each failed gate to err. The first
    # violation's cause is recorded for the JSON report unless the caller
    # already has a cause that must win (record_cause: false).
    def failed?(report, err, record_cause: true)
      overlap_notes(report).each { |note| err.puts("saboteur: #{note}") }
      found = violations(report)
      found.each { |violation| err.puts("saboteur: #{violation.message}") }
      @cause = found.first&.cause if record_cause
      found.any?
    end

    def violations(report)
      SETTINGS.filter_map do |key, (status, cause, flag)|
        limit = @limits.fetch(key)
        next if limit.nil?

        count = report.counts.fetch(status)
        next unless over?(count, limit, report.executed.size)

        Violation.new(cause: cause, message: "#{count} #{status} mutants, above #{flag} #{limit}")
      end + score_gate_violations(report)
    end

    # A machine-readable summary per score gate for the JSON report: the
    # floor, the mutants scoring under it, its score and pass/fail state,
    # the failing subjects and the matched files. nil without score gates.
    def score_gate_breakdowns(report)
      return if @score_gates.empty?

      assignment = gate_assignment(report)
      @score_gates.each_with_index.map do |gate, index|
        scored = assignment.fetch(index)
        verdict = gate_verdict(gate, scored)
        { pattern: gate["pattern"], minScore: gate["min_score"], mutants: scored.size, tested: verdict[:tested],
          score: verdict[:score]&.round(1), passed: verdict[:passed],
          failingSubjects: failing_subjects(scored), files: gate_files(scored, report) }
      end
    end

    private

    # Per-path gates (#473): each gate scores the results assigned to it by
    # gate_matching, with the run's own Score formula, and fails under its
    # floor. The failure line names the matched files (at most three, then
    # a count) and the failing subject count.
    def score_gate_violations(report)
      assignment = gate_assignment(report)
      @score_gates.each_with_index.filter_map do |gate, index|
        scored = assignment.fetch(index)
        verdict = gate_verdict(gate, scored)
        next if verdict[:passed]

        files = gate_files(scored, report)
        listed = files.first(3).join(", ")
        listed += ", +#{files.size - 3} more" if files.size > 3
        message = "score gate #{gate['pattern']}: score #{format('%.1f', verdict[:score])} "
        message += "below #{gate['min_score']} (#{scored.size} mutant(s) under it, "
        message += "#{failing_subjects(scored)} failing subject(s), #{files.size} matched file(s): #{listed})"
        Violation.new(cause: "scoreGate", message:)
      end
    end

    # A gate that lost subjects to a more specific gate says so once per
    # subject, even on a passing run. Only a gate that matched nothing at
    # all is vacuous; a fully shadowed gate reads as overlapped instead.
    def overlap_notes(report)
      matched, assignment = gate_matching(report)
      @score_gates.each_with_index.filter_map do |gate, index|
        lost = (matched[index] - assignment.fetch(index)).map(&:subject).uniq.size
        if lost.positive?
          next "score gate #{gate['pattern']}: #{lost} subject(s) also match a more specific gate and score there"
        end

        next if Score.of(assignment.fetch(index)).tested.positive?

        # A gate that matched mutants but tested none of them (errors,
        # timeouts, skips) passes just as vacuously as one that matched
        # nothing; say so either way, unless a more specific gate shadows it.
        if matched[index].empty?
          "score gate #{gate['pattern']}: nothing executed under it, passing vacuously"
        else
          "score gate #{gate['pattern']}: no mutant(s) tested under it, passing vacuously"
        end
      end
    end

    # One verdict per gate, shared by the console violation and the JSON
    # breakdown: both judge the unrounded score, so a 79.96 against an 80
    # floor fails in both places. The one-decimal score in the JSON is
    # display-only. A gate with nothing tested passes vacuously, score nil.
    def gate_verdict(gate, scored)
      breakdown = Score.of(scored)
      return { tested: 0, passed: true } if breakdown.tested.zero?

      raw = breakdown.value * 100
      { tested: breakdown.tested, score: raw, passed: raw >= gate["min_score"] }
    end

    # Each result scores under the single most specific matching gate: more
    # literal (non-glob) pattern characters win, ties keep the earlier config
    # entry (min_by returns the first minimum), so overlapping floors never
    # double-count a mutant. Returns the per-gate matched and assigned lists.
    def gate_matching(report)
      matched = @score_gates.map { [] }
      assignment = @score_gates.map { [] }
      if @score_gates.any?
        each_relative_result(report).each do |relative, result|
          candidates = @score_gates.each_with_index.select { |gate, _index| gate_matches?(gate, relative) }
          candidates.each { |candidate| matched[candidate[1]] << result }
          winner = candidates.min_by { |gate, _index| -specificity(gate["pattern"]) }
          assignment[winner[1]] << result if winner
        end
      end
      [matched, assignment]
    end

    def gate_assignment(report)
      gate_matching(report)[1]
    end

    # [relative path, result] pairs; the caller consumes the array, so the
    # build cannot be swapped for a side-effect-only walk.
    def each_relative_result(report)
      prefix = File.join(File.realpath(report.root), "")
      report.results.map { |result| [result.subject.file.delete_prefix(prefix), result] }
    end

    def gate_matches?(gate, relative)
      File.fnmatch?(gate["pattern"], relative, File::FNM_PATHNAME | File::FNM_EXTGLOB)
    end

    # Literal characters pin a gate to its files; glob metacharacters do
    # not, and a {a,b} brace group counts once rather than per alternative,
    # so the exact lib/saboteur/gates.rb outranks lib/saboteur/{gates,config}.rb.
    def specificity(pattern)
      pattern.gsub(/\{[^{}]*\}/, "x").gsub(/[*?\[\]\\]/, "").length
    end

    def gate_files(scored, report)
      prefix = File.join(File.realpath(report.root), "")
      scored.map { |result| result.subject.file.delete_prefix(prefix) }.uniq.sort
    end

    # A subject fails a gate when at least one of its mutants survived.
    def failing_subjects(scored)
      scored.select(&:survived?).map(&:subject).uniq.size
    end

    def over?(count, limit, executed)
      return count > limit if limit.is_a?(Integer)

      count * 100 > limit.to_i * executed
    end
  end
end
