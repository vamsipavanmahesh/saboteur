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

    # Prints each failed gate to err and remembers the first one's cause for the JSON report.
    def failed?(report, err)
      vacuous_gates(report).each { |note| err.puts("saboteur: #{note}") }
      found = violations(report)
      found.each { |violation| err.puts("saboteur: #{violation.message}") }
      @cause = found.first&.cause
      !@cause.nil?
    end

    def violations(report)
      SETTINGS.filter_map do |key, (status, cause, flag)|
        limit = @limits.fetch(key)
        count = report.counts.fetch(status)
        next if limit.nil? || !over?(count, limit, report.executed.size)

        Violation.new(cause: cause, message: "#{count} #{status} mutants, above #{flag} #{limit}")
      end + score_gate_violations(report)
    end

    private

    # Per-path gates (#473): each gate scores the results whose subject file
    # (root-relative) matches its pattern, with the run's own Score formula,
    # and fails under its floor.
    def score_gate_violations(report)
      @score_gates.filter_map do |gate|
        scored = score_gate_subset(gate, report)
        breakdown = Score.of(scored)
        next if breakdown.tested.zero?

        score = breakdown.value * 100
        next if score >= gate["min_score"]

        Violation.new(cause: "scoreGate",
                      message: "score gate #{gate['pattern']}: score #{format('%.1f', score)} below " \
                               "#{gate['min_score']} (#{scored.size} mutants under it)")
      end
    end

    # A gate with nothing executed under it passes vacuously and says so.
    def vacuous_gates(report)
      @score_gates.filter_map do |gate|
        breakdown = Score.of(score_gate_subset(gate, report))
        "score gate #{gate['pattern']}: nothing executed under it, passing vacuously" if breakdown.tested.zero?
      end
    end

    def score_gate_subset(gate, report)
      prefix = "#{report.root}/"
      report.results.select do |result|
        relative = result.subject.file.delete_prefix(prefix)
        File.fnmatch?(gate["pattern"], relative, File::FNM_PATHNAME | File::FNM_EXTGLOB)
      end
    end

    def over?(count, limit, executed)
      return count > limit if limit.is_a?(Integer)

      count * 100 > limit.to_i * executed
    end
  end
end
