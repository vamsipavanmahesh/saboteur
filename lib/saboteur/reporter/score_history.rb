# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "time"
require "digest"
require "fileutils"
require_relative "agent_incomplete"
require_relative "history_record"

module Saboteur
  module Reporter
    # Opt-in append-only score observations, not a baseline or a CI gate.
    class ScoreHistory
      DIFFERENT_RUN = "score history: change unavailable (different selection/inventory or incomplete run)"
      MISSING_SCORE = "score history: change unavailable (no tested mutants)"
      MAX_RECORD_BYTES = 64 * 1024
      OPEN_FLAGS = File::RDWR | File::CREAT | File::NONBLOCK | File::NOFOLLOW

      def initialize(path)
        @path = path
      end

      def append(report, head:, scope:)
        record = build(report, head, scope)
        HistoryRecord.validate(record)
        line = "#{JSON.generate(record)}\n"
        raise Error, "score history record exceeds byte limit" if line.bytesize > MAX_RECORD_BYTES

        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, OPEN_FLAGS, 0o600) do |file|
          regular_file(file)
          lock(file, File::LOCK_EX)

          previous = previous_record(file)
          file.seek(0, IO::SEEK_END)
          file.write(line)
          file.flush
          change(previous, record)
        end
      rescue SystemCallError, IOError, JSON::ParserError, KeyError, TypeError => e
        raise Error, "score history was not recorded: #{e.message}"
      end

      def validate_existing
        return unless File.exist?(@path) || File.symlink?(@path)

        File.open(@path, File::RDONLY | File::NONBLOCK | File::NOFOLLOW) do |file|
          regular_file(file)
          lock(file, File::LOCK_SH)

          previous_record(file)
        end
      rescue SystemCallError, IOError => e
        raise Error, "score history cannot be read: #{e.message}"
      end

      private

      def build(report, head, scope)
        { "version" => 2, "date" => Time.now.utc.iso8601, "commit" => head,
          "selection" => Digest::SHA256.hexdigest(JSON.generate(scope.sort_by { |key, _| key.to_s }.to_h)),
          "inventory" => Digest::SHA256.hexdigest(JSON.generate(report.results.map(&:digest).sort)),
          "score" => overall_score(report), "coveredScore" => report.score,
          "counts" => report.counts.transform_keys(&:to_s),
          "breakdown" => report.score_breakdown.to_h.transform_keys(&:to_s),
          "incomplete" => incompleteness(report), "operatorPolicy" => report.operator_policy }
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

      def lock(file, mode)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        until file.flock(mode | File::LOCK_NB)
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            raise Error,
                  "score history lock was not acquired"
          end

          sleep 0.01
        end
      end

      def regular_file(file)
        raise Error, "score history must be a regular file" unless file.stat.file?
      end

      def previous_record(file)
        while (line = file.gets(MAX_RECORD_BYTES + 1))
          raise Error, "score history record exceeds byte limit" if line.bytesize > MAX_RECORD_BYTES
          raise Error, "score history contains a truncated record" unless line.end_with?("\n")

          previous = HistoryRecord.parse(line)
        end
        previous
      end

      def change(previous, current)
        return "score history: first record" unless previous
        return DIFFERENT_RUN unless
          previous["selection"] == current["selection"] && previous["inventory"] == current["inventory"] &&
          previous["incomplete"].empty? && current["incomplete"].empty?
        return MISSING_SCORE if
          previous["coveredScore"].nil? || current["coveredScore"].nil?

        delta = (current["coveredScore"] - previous["coveredScore"]) * 100
        format("score history: covered score change %+.2f percentage points (same configured selection)", delta)
      end
    end
  end
end
