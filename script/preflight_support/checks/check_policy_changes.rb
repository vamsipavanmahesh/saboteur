# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  module Checks
    # Reports changes to files that define how checks judge the code: lint limits, dependencies, the
    # harness itself and the mutation config. GitHub does not protect all of these, so the result is
    # a review-required notice, never a claim of protection. It does not stop the other checks, but a
    # run with this notice is never reported as automatic_checks_passed.
    class CheckPolicyChanges
      EXACT = %w[.rubocop.yml .rspec Gemfile Gemfile.lock saboteur.gemspec Rakefile].freeze
      PREFIXES = %w[script/preflight script/preflight_support spec/script/preflight spec/support config/].freeze

      def initialize(repository:)
        @repository = repository
      end

      def call(_context = nil)
        hits = @repository.changes.map(&:path).select { |path| policy_file?(path) }
        return CheckResult.new(name: "check_policy_changes", status: :passed) if hits.empty?

        CheckResult.new(name: "check_policy_changes", status: :review_required,
                        reason: "files that define how checks judge code changed; review the diff, do not compare " \
                                "this run with earlier green runs",
                        details: hits.map { |path| "review required (not necessarily protected by GitHub): #{path}" })
      end

      private

      def policy_file?(path)
        EXACT.include?(path) || PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix.chomp('/')}/") }
      end
    end
  end
end
