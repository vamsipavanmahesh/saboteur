# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "time"
require_relative "history_policy"

module Saboteur
  module Reporter
    # Strict version-one observation schema. Never repairs imported evidence.
    module HistoryRecord
      FIELDS = %w[version date commit selection inventory score coveredScore counts breakdown incomplete].freeze
      BREAKDOWN = %w[score tested assertionKills crashKills unclassifiedKills timeouts survivors
                     assertionShare crashShare].freeze
      COUNTS = STATUSES.map(&:to_s).freeze

      class UniqueObject < Hash
        def []=(key, value)
          raise Error, "score history contains duplicate keys" if key?(key)

          super
        end
      end

      extend HistoryPolicy

      module_function

      def parse(line)
        record = JSON.parse(line, object_class: UniqueObject)
        validate(record)
        record
      rescue JSON::ParserError, ArgumentError, TypeError => e
        raise Error, "score history contains an invalid record: #{e.message}"
      end

      def validate(record)
        validate_header(record, FIELDS)

        date(record.fetch("date"))
        commit = record.fetch("commit")
        raise Error, "score history contains an invalid commit" unless commit.nil? || sha?(commit, 40)

        %w[selection inventory].each do |key|
          raise Error, "score history contains an invalid digest" unless sha?(record.fetch(key), 64)
        end
        %w[score coveredScore].each { |key| fraction(record.fetch(key)) }
        counts = record.fetch("counts")
        fields(counts, COUNTS)
        counts.each_value { |value| count(value) }
        breakdown(record.fetch("breakdown"), counts, record.fetch("coveredScore"))
        score_consistency(record)
        reasons(record.fetch("incomplete"))
      end

      def date(value)
        return if Time.iso8601(value).utc.iso8601 == value

        raise Error,
              "score history contains an invalid date"
      rescue ArgumentError, TypeError, NoMethodError => e
        raise Error, "score history contains an invalid date: #{e.message}"
      end

      def reasons(value)
        unless value.is_a?(Array) && value.all? do |reason|
          reason.is_a?(String) && !reason.empty?
        end && value.uniq == value
          raise Error, "score history contains invalid incomplete reasons"
        end
      end

      def score_consistency(record)
        value = record.fetch("breakdown")
        detected = value.values_at("assertionKills", "crashKills", "unclassifiedKills", "timeouts").sum
        tested = value.fetch("tested")
        expected = tested.zero? ? nil : detected.fdiv(tested)
        raise Error, "score history contains an inconsistent score" unless record.fetch("coveredScore") == expected

        %w[assertion crash].each do |kind|
          expected_share = tested.zero? ? nil : value.fetch("#{kind}Kills").fdiv(tested)
          unless value.fetch("#{kind}Share") == expected_share
            raise Error,
                  "score history contains an inconsistent share"
          end
        end
        overall = record.fetch("score")
        return unless overall && ((record.fetch("coveredScore").nil? && !overall.zero?) ||
                          (record.fetch("coveredScore") && overall > record.fetch("coveredScore")))

        raise Error, "score history contains an inconsistent overall score"
      end

      def fields(object, expected)
        return if object.is_a?(Hash) && object.keys.sort == expected.sort

        raise Error,
              "score history contains an invalid record schema"
      end

      def sha?(value, length)
        value.is_a?(String) && value.match?(/\A[0-9a-f]{#{length}}\z/)
      end

      def fraction(value)
        return if value.nil? || (0..1).cover?(value)

        raise Error,
              "score history contains an invalid score"
      end

      def count(value)
        raise Error, "score history contains an invalid count" unless value.is_a?(Integer) && value >= 0
      end

      def breakdown(value, counts, covered)
        fields(value, BREAKDOWN)
        %w[score assertionShare crashShare].each { |key| fraction(value.fetch(key)) }
        (BREAKDOWN - %w[score assertionShare crashShare]).each { |key| count(value.fetch(key)) }
        kills = value.values_at("assertionKills", "crashKills", "unclassifiedKills").sum
        tested = counts.values_at("killed", "survived", "timeout").sum
        unless kills == counts.fetch("killed") && value.fetch("tested") == tested &&
               value.fetch("timeouts") == counts.fetch("timeout") &&
               value.fetch("survivors") == counts.fetch("survived") &&
               value.fetch("score") == covered
          raise Error, "score history contains inconsistent counts"
        end
      end
    end
  end
end
