# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  module Checks
    # git diff --check over the exact range: trailing whitespace, conflict markers.
    class Whitespace
      def initialize(repository:, command_runner:, head:)
        @repository = repository
        @runner = command_runner
        @head = head
      end

      def call(_context = nil)
        result = @runner.run(["git", "diff", "--check", @repository.merge_base, @head])
        return CheckResult.new(name: "diff_check", status: :passed, commands: [result]) if result.succeeded?

        status = result.ran? && result.exit_status == 2 ? :failed : :incomplete
        CheckResult.new(name: "diff_check", status: status, reason: "git diff --check reported problems",
                        details: result.stdout.lines.first(20).map(&:chomp), commands: [result])
      end
    end
  end
end
