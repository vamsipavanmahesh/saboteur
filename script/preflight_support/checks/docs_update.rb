# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  module Checks
    # AGENTS.md requires a docs/ update with any change to CLI flags, behavior or usage. This only sees
    # whether a docs/ file changed alongside the CLI files. It cannot tell whether the update is right.
    class DocsUpdate
      CLI_FILES = %r{\A(lib/saboteur/(cli|help)\.rb|exe/.+)\z}

      def initialize(repository:)
        @repository = repository
      end

      def call(_context = nil)
        paths = @repository.changes.map(&:path)
        cli = paths.grep(CLI_FILES)
        return result(:not_applicable, "no CLI entry files changed") if cli.empty?
        return result(:passed, nil) if paths.any? { |path| path.start_with?("docs/") }

        result(:review_required,
               "CLI files changed (#{cli.join(', ')}) but docs/ did not; it must change if flags or behavior did")
      end

      private

      def result(status, reason)
        CheckResult.new(name: "docs_update", status: status, reason: reason)
      end
    end
  end
end
