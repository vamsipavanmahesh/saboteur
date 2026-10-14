# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  module Checks
    # AGENTS.md requires a README update with any change to CLI flags, behavior or usage. This only sees
    # whether README.md changed alongside the CLI files. It cannot tell whether the update is right.
    class ReadmeUpdate
      CLI_FILES = %r{\A(lib/saboteur/(cli|help)\.rb|exe/.+)\z}

      def initialize(repository:)
        @repository = repository
      end

      def call(_context = nil)
        paths = @repository.changes.map(&:path)
        cli = paths.grep(CLI_FILES)
        return result(:not_applicable, "no CLI entry files changed") if cli.empty?
        return result(:passed, nil) if paths.include?("README.md")

        result(:review_required,
               "CLI files changed (#{cli.join(', ')}) but README.md did not; it must change if flags or behavior did")
      end

      private

      def result(status, reason)
        CheckResult.new(name: "readme_update", status: status, reason: reason)
      end
    end
  end
end
