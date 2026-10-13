# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "time"
require "digest"
require "fileutils"
require_relative "agent_incomplete"

module Saboteur
  module Reporter
    # Opt-in append-only score observations, not a baseline or a CI gate.
    class ScoreHistory
      def initialize(path)
        @path = path
      end

      def append(report, head:, scope:)
        record = build(report, head, scope)
        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, File::RDWR | File::CREAT, 0o600) do |file|
          raise Error, "score history lock was not acquired" unless file.flock(File::LOCK_EX)

          previous = previous_record(file)
          file.seek(0, IO::SEEK_END)
          file.write("#{JSON.generate(record)}\n")
          file.flush
          change(previous, record)
        end
      rescue SystemCallError, IOError, JSON::ParserError, KeyError, TypeError => e
        raise Error, "score history was not recorded: #{e.message}"
      end

      private

      def build(report, head, scope)
        { "version" => 1, "date" => Time.now.utc.iso8601, "commit" => head,
          "selection" => Digest::SHA256.hexdigest(JSON.generate(scope.sort_by { |key, _| key.to_s }.to_h)),
          "inventory" => Digest::SHA256.hexdigest(JSON.generate(report.results.map(&:digest).sort)),
          "score" => overall_score(report), "coveredScore" => report.score,
          "counts" => report.counts.transform_keys(&:to_s),
          "breakdown" => report.score_breakdown.to_h,
          "incomplete" => incompleteness(report) }
      end

      def overall_score(report)
        score = report.score_breakdown
        missing = report.results.count { |result| result.status == :skipped && result.reason == "no coverage" }
        denominator = score.tested + missing
        denominator.zero? ? nil : score.detected.fdiv(denominator)
      end

      def incompleteness(report)
        reasons = Agent::Incomplete.reasons(report).map { |reason| reason[:reason] }
        reasons << "baseline_incomplete" if report.run_evidence && !report.run_evidence["complete"]
        reasons << "omissions" unless report.omissions.empty?
        reasons.uniq
      end

      def previous_record(file)
        previous = nil
        file.each_line do |line|
          unless line.end_with?("\n")
            raise Error,
                  "score history contains a truncated record; existing file was not changed"
          end

          previous = JSON.parse(line)
          unless previous.is_a?(Hash) && previous["version"] == 1 && previous.key?("coveredScore") &&
                 previous["selection"].is_a?(String) && previous["inventory"].is_a?(String) &&
                 previous["incomplete"].is_a?(Array)
            raise Error, "score history contains an invalid record; existing file was not changed"
          end

          score = previous["coveredScore"]
          unless score.nil? || (score.is_a?(Numeric) && (0..1).cover?(score))
            raise Error, "score history contains an invalid score; existing file was not changed"
          end
        end
        previous
      end

      def change(previous, current)
        return "score history: first record" unless previous
        return "score history: change unavailable (different selection/inventory or incomplete run)" unless
          previous["selection"] == current["selection"] && previous["inventory"] == current["inventory"] &&
          previous["incomplete"].empty? && current["incomplete"].empty?
        return "score history: change unavailable (no tested mutants)" if
          previous["coveredScore"].nil? || current["coveredScore"].nil?

        delta = (current["coveredScore"] - previous["coveredScore"]) * 100
        format("score history: covered score change %+.2f percentage points (same configured selection)", delta)
      end
    end
  end
end
