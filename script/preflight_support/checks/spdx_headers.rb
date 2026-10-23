# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  module Checks
    # Same file set and fixture exemption as the CI SPDX step, limited to files this change touches.
    class SpdxHeaders
      HEADER = "SPDX-License-Identifier: MIT"
      EXEMPT = %r{\A(spec/fixtures/projects|acceptance/fixtures)/}
      COVERED = %r{(\.rb|\.gemspec)\z|\Aexe/[^/]+\z|\A(Gemfile|Rakefile)\z|\Ascript/preflight\z}

      def initialize(repository:, head:)
        @repository = repository
        @head = head
      end

      def call(_context = nil)
        missing = candidates.reject { |path| @repository.blob_at(@head, path)&.include?(HEADER) }
        status = missing.empty? ? :passed : :failed
        CheckResult.new(name: "spdx_headers", status: status, details: missing.map { |path| "missing header: #{path}" },
                        reason: missing.empty? ? nil : "files lack the #{HEADER} header")
      end

      private

      def candidates
        @repository.changes.reject { |change| change.status == "D" }.map(&:path)
                   .select { |path| path.match?(COVERED) && !path.match?(EXEMPT) }
      end
    end
  end
end
