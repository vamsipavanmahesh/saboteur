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
      MARKER_PATTERN = /\A<!-- #{MARKER}(\h{8,64}) -->/
      HTTPS_URL = %r{\Ahttps://\S+\z}
      # Bidirectional overrides, zero-width marks and control characters other than tab and newline.
      UNSAFE_TEXT = /[\u202a-\u202e\u2066-\u2069\u200b-\u200f\u2060\u061c\ufeff\u0000-\u0008\u000b-\u001f\u007f]/
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
        #
        # locate: maps a finding to the line its comment goes on, or nil when
        # that line cannot be placed on the pull request. A finding it cannot
        # place is counted in the summary, never moved on a guess. The default
        # is the first changed line.
        def plan(findings, existing: [], limit: DEFAULT_LIMIT, run_url: nil, complete: false,
                 locate: ->(finding) { finding["changedLines"].first })
          posted = digests_of(existing)
          candidates = candidates(findings)
          fresh = candidates.reject { |finding| posted.key?(finding["digest"]) }
          gone = complete == true ? stale(posted, findings) : {}
          room = [Integer(limit) - (posted.size - gone.size), 0].max
          posts = place(fresh, room, locate)
          Plan.new(post: posts, delete: gone.values,
                   summary: summary(findings, fresh.size - posts.size, run_url))
        end

        def body(finding)
          opening = "**Surviving mutant** (`#{word(finding['operator'])}`)#{in_subject(finding)}: " \
                    "this change did not make any test fail."
          [marker(finding["digest"]), opening,
           "",
           fenced(finding["original"], "Original"),
           fenced(finding["replacement"], "Mutant"),
           "",
           hint(finding["classification"])].join("\n")
        end

        # A summary comment the bot left: the marker must lead the body.
        def summary_comment?(body)
          body.to_s.start_with?(SUMMARY_MARKER)
        end

        def marker(digest)
          "<!-- #{MARKER}#{digest} -->"
        end

        private

        # Up to room comments, each on a line locate accepts. A finding it
        # refuses is skipped, and the next one takes its room.
        def place(fresh, room, locate)
          posts = []
          fresh.each do |finding|
            break if posts.size >= room

            line = locate.call(finding)
            posts << comment(finding, line) if usable_line?(line)
          end
          posts
        end

        def comment(finding, line)
          { path: finding["path"], line: line, digest: finding["digest"], body: body(finding) }
        end

        def candidates(findings)
          Array(findings["survivors"]).select do |finding|
            DIGEST.match?(finding["digest"].to_s) && finding["path"].is_a?(String) &&
              finding["changedLines"].is_a?(Array) && usable_line?(finding["changedLines"].first) &&
              !QUIET.include?(finding["classification"])
          end
        end

        def usable_line?(line)
          line.is_a?(Integer) && line.positive?
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
          return {} unless findings["survivors"].is_a?(Array) && findings["survivorsTruncated"].to_i.zero?

          live = Array(findings["survivors"]).map { |finding| finding["digest"] }
          posted.except(*live)
        end

        def summary(findings, not_posted, run_url)
          left_out = not_posted + findings["survivorsTruncated"].to_i
          return nil if left_out.zero?

          text = "#{SUMMARY_MARKER}\n#{left_out} more surviving mutant#{'s' unless left_out == 1} " \
                 "not shown as comments."
          HTTPS_URL.match?(run_url.to_s) ? "#{text} Full report: #{run_url}" : text
        end

        def hint(label)
          HINTS.fetch(label, DEFAULT_HINT)
        end

        # The subject rides in the opening line: notification mail shows the
        # body without its diff (#1212). Empty when there is none.
        def in_subject(finding)
          finding["subject"].to_s.gsub(/[`\r\n]/, "")[0, 60].then { |name| name.empty? ? "" : " in `#{name}`" }
        end

        def word(text)
          text.to_s.gsub(/[^\w:.-]/, "")[0, 40]
        end

        def fenced(text, label)
          code = text.to_s.scrub.gsub(UNSAFE_TEXT, "")[0, MAX_TEXT]
          fence = "`" * [3, code.scan(/`{1,}/).map(&:size).max.to_i + 1].max
          "#{label}:\n#{fence}ruby\n#{code}\n#{fence}"
        end
      end
    end
  end
end
