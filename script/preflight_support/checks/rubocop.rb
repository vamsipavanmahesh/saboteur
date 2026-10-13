# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  module Checks
    # Full RuboCop with the repository's own .rubocop.yml. The JSON report is validated strictly:
    # required fields with the right types, non-negative counts that match the file and offense lists, and
    # proof that files were inspected. It must also agree with the process exit status. Anything odd is incomplete.
    class Rubocop
      COMMAND = %w[bundle exec rubocop --format json].freeze

      def initialize(command_runner:)
        @runner = command_runner
      end

      def call(_context = nil)
        result = @runner.run(COMMAND)
        return incomplete(result, "could not use RuboCop: #{result.problem}") unless result.ran?

        report = StrictJson.parse(result.stdout)
        problem = shape_problem(report)
        return incomplete(result, "RuboCop report rejected: #{problem}") if problem

        verdict(result, report)
      rescue MalformedDocument => e
        incomplete(result, "RuboCop report rejected: #{e.message}")
      end

      private

      def verdict(result, report)
        offenses = report["files"].flat_map { |file| file["offenses"].map { |offense| describe(file, offense) } }
        unless result.exit_status.zero? == offenses.empty?
          return incomplete(result,
                            "RuboCop report disagrees with its exit status")
        end
        return CheckResult.new(name: "rubocop", status: :passed, commands: [result]) if offenses.empty?

        CheckResult.new(name: "rubocop", status: :failed, reason: "#{offenses.size} offense(s)",
                        details: offenses.first(30), commands: [result])
      end

      def shape_problem(report)
        return "not an object" unless report.is_a?(Hash)

        files = report["files"]
        summary = report["summary"]
        return "files is not a list" unless files.is_a?(Array)
        return "summary is not an object" unless summary.is_a?(Hash)

        counts = %w[offense_count target_file_count inspected_file_count].map { |key| summary[key] }
        return "summary counts are not non-negative integers" unless counts.all? { |value| StrictJson.count?(value) }

        inventory_problem(files, *counts)
      end

      def inventory_problem(files, offense_count, target_count, inspected_count)
        return "no files were inspected" if files.empty? || target_count.zero?
        unless files.size == inspected_count && inspected_count == target_count
          return "file list does not match the summary"
        end
        return "a file entry is malformed" unless files.all? { |file| valid_file?(file) }

        total = files.sum { |file| file["offenses"].size }
        "offense count does not match the offenses listed" unless total == offense_count
      end

      def valid_file?(file)
        file.is_a?(Hash) && file["path"].is_a?(String) && file["offenses"].is_a?(Array) &&
          file["offenses"].all? { |offense| valid_offense?(offense) }
      end

      def valid_offense?(offense)
        offense.is_a?(Hash) && offense["cop_name"].is_a?(String) && offense["message"].is_a?(String) &&
          offense["location"].is_a?(Hash) && StrictJson.count?(offense.dig("location", "start_line"))
      end

      def describe(file, offense)
        "#{file['path']}:#{offense.dig('location', 'start_line')} #{offense['cop_name']}: #{offense['message']}"
      end

      def incomplete(result, reason)
        CheckResult.new(name: "rubocop", status: :incomplete, reason: reason, commands: [result].compact)
      end
    end
  end
end
