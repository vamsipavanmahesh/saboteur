# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Preflight
  module Checks
    # Every non-merge commit needs a Signed-off-by line equal to its author, and no AI attribution.
    class Signoff
      # Matches known AI tool and bot identities only: the whole trailer name, or a known vendor address.
      # A human with a similar name or address is not matched. The list is a heuristic and will miss tools
      # it does not know; it is a guard rail, not proof.
      AI_NAME = /(claude( code)?|chatgpt|codex|copilot|gemini|cursor( agent)?|devin|openai|anthropic|[\w-]+\[bot\])/i
      AI_EMAIL = /@(anthropic|openai)\.com\b|\[bot\]@users\.noreply\.github\.com/i
      TRAILER = /\Aco-authored-by:\s*(?<name>[^<]*?)\s*<(?<email>[^>]*)>\s*\z/i
      GENERATED = /\Agenerated (with|by) #{AI_NAME.source}(\s|\z)/i

      def initialize(repository:)
        @repository = repository
      end

      def call(_context = nil)
        problems = @repository.commits.flat_map { |sha| problems_for(sha) }
        status = problems.empty? ? :passed : :failed
        CheckResult.new(name: "dco_signoff", status: status, details: problems,
                        reason: problems.empty? ? nil : "commits need a matching sign-off and no AI attribution")
      rescue UnverifiableInput => e
        CheckResult.new(name: "dco_signoff", status: :incomplete, reason: e.message)
      end

      private

      def ai_attribution?(line)
        return true if line.match?(GENERATED)

        trailer = line.match(TRAILER)
        trailer && (trailer[:name].match?(/\A#{AI_NAME.source}\z/i) || trailer[:email].match?(AI_EMAIL))
      end

      def problems_for(sha)
        author = @repository.capture!(["log", "-1", "--format=%an <%ae>", sha.to_s]).chomp
        lines = @repository.capture!(%W[log -1 --format=%B #{sha}]).split("\n").map(&:chomp)
        found = []
        unless lines.include?("Signed-off-by: #{author}")
          found << "#{sha}: no line exactly equal to 'Signed-off-by: #{author}'"
        end
        found << "#{sha}: AI attribution trailer" if lines.any? { |line| ai_attribution?(line) }
        found
      end
    end
  end
end
