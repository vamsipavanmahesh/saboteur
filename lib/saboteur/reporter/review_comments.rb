# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Pull-request review comments for surviving mutants (#246): decides what
    # to post, keep and delete from a report's findings and the comments the
    # action's bot already left, and builds the comment text. Pure: the
    # GitHub calls live in action/post-review-comments.
    #
    # Everything in a finding comes from the pull request's own code, so it
    # is untrusted: the body is a fixed template, mutation text sits in a
    # code fence longer than any backtick run inside it, and the few fields
    # that are not code (operator, digest) are filtered to a safe alphabet.
    module ReviewComments
      MARKER = "saboteur:digest="
      SUMMARY_MARKER = "<!-- saboteur:summary -->"
      DEFAULT_LIMIT = 10
      MAX_TEXT = 200
      DIGEST = /\A\h{8,64}\z/
      MARKER_PATTERN = /<!-- #{MARKER}(\h{8,64}) -->/
      # Labels whose survivors are probably noise: never worth a comment.
      QUIET = %w[likely_equivalent arid].freeze

      HINTS = {
        "missing_test" => "A test reaches this line and still passes with the change. " \
                          "Add an assertion that pins this behaviour.",
        "tool_limit" => "Saboteur could not observe this mutant faithfully. Check it by hand."
      }.freeze
      DEFAULT_HINT = "No test fails with this change. Check whether a test should pin it."

      Plan = Struct.new(:post, :delete, :summary, keyword_init: true)

      class << self
        # findings: the report's saboteur.findings hash (string keys).
        # existing: the bot's review comments, as hashes with "id" and "body".
        # Returns post (path, line, digest, body), delete (comment ids) and
        # summary (text, or nil when nothing was left out).
        def plan(findings, existing: [], limit: DEFAULT_LIMIT, run_url: nil)
          posted = digests_of(existing)
          candidates = candidates(findings)
          fresh = candidates.reject { |finding| posted.key?(finding["digest"]) }
          gone = stale(posted, findings)
          room = [Integer(limit) - (posted.size - gone.size), 0].max
          Plan.new(post: fresh.first(room).map { |finding| comment(finding) }, delete: gone.values,
                   summary: summary(findings, fresh, room, run_url))
        end

        def body(finding)
          [marker(finding["digest"]),
           "**Surviving mutant** (`#{word(finding['operator'])}`): this change did not make any test fail.",
           "",
           fenced(finding["original"], "Original"),
           fenced(finding["replacement"], "Mutant"),
           "",
           hint(finding["classification"])].join("\n")
        end

        def marker(digest)
          "<!-- #{MARKER}#{digest} -->"
        end

        private

        def comment(finding)
          { path: finding["path"], line: finding["changedLines"].first, digest: finding["digest"],
            body: body(finding) }
        end

        def candidates(findings)
          Array(findings["survivors"]).select do |finding|
            DIGEST.match?(finding["digest"].to_s) && finding["path"].is_a?(String) &&
              !Array(finding["changedLines"]).empty? && !QUIET.include?(finding["classification"])
          end
        end

        def digests_of(existing)
          existing.each_with_object({}) do |comment, found|
            digest = comment["body"].to_s[MARKER_PATTERN, 1]
            found[digest] = comment["id"] if digest
          end
        end

        # Posted digests that are no longer survivors. Only decided when the
        # findings list every live survivor; a truncated list says nothing
        # about the ones it left out, so nothing is deleted then.
        def stale(posted, findings)
          return {} unless findings["survivorsTruncated"].to_i.zero?

          live = Array(findings["survivors"]).map { |finding| finding["digest"] }
          posted.except(*live)
        end

        def summary(findings, fresh, room, run_url)
          left_out = [fresh.size - room, 0].max + findings["survivorsTruncated"].to_i
          return nil if left_out.zero?

          text = "#{SUMMARY_MARKER}\n#{left_out} more surviving mutant#{'s' unless left_out == 1} " \
                 "not shown as comments."
          run_url ? "#{text} Full report: #{run_url}" : text
        end

        def hint(label)
          HINTS.fetch(label, DEFAULT_HINT)
        end

        def word(text)
          text.to_s.gsub(/[^\w:.-]/, "")[0, 40]
        end

        def fenced(text, label)
          code = text.to_s.scrub[0, MAX_TEXT]
          fence = "`" * [3, code.scan(/`{1,}/).map(&:size).max.to_i + 1].max
          "#{label}:\n#{fence}ruby\n#{code}\n#{fence}"
        end
      end
    end
  end
end
