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
    end

    attr_reader :cause

    def any?
      @limits.values.any?
    end

    # --max-errors judges errored mutants, so a threshold run tolerates them.
    def judges_errors?
      !@limits.fetch("max_errors").nil?
    end

    # Prints each failed gate to err and remembers the first one's cause for the JSON report.
    def failed?(report, err)
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
      end
    end

    private

    def over?(count, limit, executed)
      return count > limit if limit.is_a?(Integer)

      count * 100 > limit.to_i * executed
    end
  end
end
