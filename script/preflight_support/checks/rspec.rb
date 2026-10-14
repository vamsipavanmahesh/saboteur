# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "fileutils"

module Preflight
  module Checks
    # Runs RSpec for the given paths (none means the whole suite) and validates the JSON report strictly:
    # required fields with the right types, non-negative counts, a status for every example, counts that match
    # the example list, no load errors, at least one example. The report must also agree with the exit status.
    class Rspec
      STATUSES = %w[passed failed pending].freeze

      def initialize(name:, command_runner:, paths: [])
        @name = name
        @runner = command_runner
        @paths = paths
      end

      # The JSON goes to a pipe the harness owns (file descriptor 3), not to a path in the checkout. A
      # shell redirect moves RSpec's stdout onto it: opening /dev/fd/3 as a path is not portable (macOS
      # refuses to open a pipe through /dev/fd).
      def call(_context = nil)
        result = @runner.run(["/bin/sh", "-c", 'exec bundle exec rspec "$@" --format json >&3', "rspec"] + @paths,
                             data_pipe: true)
        return incomplete(result, "could not use RSpec: #{result.problem}") unless result.ran?
        return incomplete(result, "RSpec wrote no report") if result.data.to_s.empty?

        document = StrictJson.parse(result.data)
        problem = shape_problem(document)
        return incomplete(result, "RSpec report rejected: #{problem}") if problem

        verdict(result, document, result.data_path)
      rescue MalformedDocument => e
        incomplete(result, "RSpec report rejected: #{e.message}")
      end

      private

      def verdict(result, document, path)
        counts = document["summary"]
        examples = counts["example_count"]
        failures = counts["failure_count"]
        unless failures.zero? == result.exit_status.zero?
          return incomplete(result,
                            "RSpec summary disagrees with exit status")
        end
        if failures.zero?
          return CheckResult.new(name: @name, status: :passed, details: pass_details(counts),
                                 commands: [result])
        end

        CheckResult.new(name: @name, status: :failed, reason: "#{failures} of #{examples} examples failed",
                        details: failed_names(document, path), commands: [result])
      end

      def shape_problem(document)
        unless document.is_a?(Hash) && document["summary"].is_a?(Hash) && document["examples"].is_a?(Array)
          return "not an object"
        end

        summary = document["summary"]
        keys = %w[example_count failure_count pending_count errors_outside_of_examples_count]
        return "summary counts are not non-negative integers" unless keys.all? { |key| StrictJson.count?(summary[key]) }
        return "spec files failed to load" if summary["errors_outside_of_examples_count"].positive?
        return "zero examples ran" if summary["example_count"].zero?

        example_problem(document["examples"], summary)
      end

      def example_problem(examples, summary)
        return "an example entry is malformed" unless examples.all? do |example|
          example.is_a?(Hash) && STATUSES.include?(example["status"])
        end

        tally = examples.map { |example| example["status"] }.tally
        "example list does not match the summary" unless examples.size == summary["example_count"] &&
                                                         tally.fetch("failed", 0) == summary["failure_count"] &&
                                                         tally.fetch("pending", 0) == summary["pending_count"]
      end

      def pass_details(counts)
        ["#{counts['example_count']} examples", "#{counts['pending_count']} pending"]
      end

      def failed_names(document, path)
        failed = document["examples"].select { |example| example["status"] == "failed" }
        failed.first(20).map { |example| "#{example['file_path']}: #{example['full_description']}" } +
          ["raw report: #{path || 'not saved'}"]
      end

      def incomplete(result, reason)
        CheckResult.new(name: @name, status: :incomplete, reason: reason, commands: [result].compact)
      end
    end
  end
end
