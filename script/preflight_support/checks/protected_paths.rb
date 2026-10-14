# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"

module Preflight
  module Checks
    # Fails on any change to a protected path. The list is read from the base commit's
    # panel-gate policy, so a branch cannot edit its own protection. Active mutation
    # config files are added because the policy file does not list them yet.
    # There is no override: approval cannot come from a flag, a message or a comment.
    class ProtectedPaths
      POLICY_PATH = "script/panel-gate/policy.json"
      ACTIVE_SAFETY_PATHS = %w[config/saboteur.rb config/saboteur_ignore.rb config/saboteur_custom_map.rb].freeze

      def initialize(repository:)
        @repository = repository
      end

      # SHA-256 of the base commit's policy file, recorded in the report as the trusted-policy identity.
      def policy_digest
        text = @repository.blob_at(@repository.merge_base, POLICY_PATH)
        text && Digest::SHA256.hexdigest(text)
      end

      def call(_context = nil)
        protected_entries = load_entries
        hits = @repository.changes.select { |change| covered?(protected_entries, change.path) }
        special = @repository.changes.select { |change| special_mode?(change) }
        return failed(hits, special) unless hits.empty? && special.empty?

        CheckResult.new(name: "protected_paths", status: :passed)
      rescue UnverifiableInput, ExecutionGap => e
        CheckResult.new(name: "protected_paths", status: :incomplete, reason: e.message)
      end

      private

      def load_entries
        text = @repository.blob_at(@repository.merge_base, POLICY_PATH)
        raise UnverifiableInput, "#{POLICY_PATH} is missing at the merge base" unless text

        policy = StrictJson.parse(text)
        files = policy.is_a?(Hash) ? policy["protectedFiles"] : nil
        unless files.is_a?(Array) && files.all?(String)
          raise UnverifiableInput,
                "protectedFiles must be a list of strings"
        end

        (files + ACTIVE_SAFETY_PATHS).map { |entry| entry.chomp("/") }.reject(&:empty?)
      end

      def covered?(entries, path)
        entries.any? { |entry| path == entry || path.start_with?("#{entry}/") }
      end

      def special_mode?(change)
        [change.old_mode, change.new_mode].intersect?([Repository::SYMLINK_MODE, Repository::SUBMODULE_MODE])
      end

      def failed(hits, special)
        details = hits.map { |change| "protected: #{change.status} #{change.path}" } +
                  special.map { |change| "symlink or submodule: #{change.status} #{change.path}" }
        CheckResult.new(name: "protected_paths", status: :failed,
                        reason: "protected or special files changed; the maintainer must approve those exact edits",
                        details: details)
      end
    end
  end
end
