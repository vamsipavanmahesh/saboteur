# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Reporter::ReviewComments do
  def finding(digest, line: 12, classification: "missing_test", original: "a > b", replacement: "a >= b", **extra)
    { "digest" => digest, "path" => "lib/x.rb", "operator" => "comparison", "original" => original,
      "replacement" => replacement, "classification" => classification,
      "changedLines" => line ? [line, line + 1] : [] }.merge(extra.transform_keys(&:to_s))
  end

  def findings(*survivors, truncated: 0)
    { "survivors" => survivors, "survivorsTruncated" => truncated }
  end

  def posted(digest, id)
    { "id" => id, "body" => "#{described_class.marker(digest)}\nold text" }
  end

  describe "the comment body" do
    it "matches the recorded format" do
      expect(described_class.body(finding("aabbccdd11223344"))).to eq(<<~BODY.chomp)
        <!-- saboteur:digest=aabbccdd11223344 -->
        **Surviving mutant** (`comparison`): this change did not make any test fail.

        Original:
        ```ruby
        a > b
        ```
        Mutant:
        ```ruby
        a >= b
        ```

        A test reaches this line and still passes with the change. Add an assertion that pins this behaviour.
      BODY
    end

    it "uses the plain hint when nothing is classified, and the limit hint for tool_limit" do
      expect(described_class.body(finding("aabbccdd11223344", classification: nil)))
        .to end_with("No test fails with this change. Check whether a test should pin it.")
      expect(described_class.body(finding("aabbccdd11223344", classification: "tool_limit")))
        .to end_with("Saboteur could not observe this mutant faithfully. Check it by hand.")
    end

    it "fences code longer than any backtick run inside it" do
      body = described_class.body(finding("aabbccdd11223344", replacement: "x = ``` + ````` + @team #1"))

      expect(body).to include("``````ruby\nx = ``` + ````` + @team #1\n``````")
    end

    it "cuts long mutation text and drops anything but word characters from the operator" do
      body = described_class.body(finding("aabbccdd11223344", original: "z" * 500, operator: "x`](http://e.v) @all"))

      expect(body).to include("z" * 200).and(satisfy { |text| !text.include?("z" * 201) })
      expect(body).to include("(`xhttp:e.vall`)")
    end
  end

  describe "the code fence" do
    def fence_of(replacement)
      body = described_class.body(finding("aabbccdd11223344", replacement: replacement))
      body[/^(`+)ruby\n#{Regexp.escape(replacement)}/, 1]
    end

    it "is three backticks unless the code holds a run of three or more" do
      expect(fence_of("no ticks")).to eq("```")
      expect(fence_of("a ` b")).to eq("```")
      expect(fence_of("a `` b")).to eq("```")
      expect(fence_of("a ``` b")).to eq("````")
      expect(fence_of("`` and ````")).to eq("`````")
    end

    it "writes missing text as an empty block, and keeps 40 characters of the operator" do
      body = described_class.body(finding("aabbccdd11223344", original: nil, operator: "o" * 50))

      expect(body).to include("Original:\n```ruby\n\n```").and include("(`#{'o' * 40}`)")
      expect(described_class.body(finding("aabbccdd11223344", operator: nil))).to include("(``)")
    end
  end

  describe ".plan" do
    it "keeps every comment already posted when they exceed the limit, and posts no more" do
      plan = described_class.plan(findings(*%w[01 02 03 04].map { |n| finding("aabbccdd112233#{n}") }),
                                  existing: %w[01 02 03].map { |n| posted("aabbccdd112233#{n}", n.to_i) }, limit: 2)

      expect(plan.post).to eq([])
      expect(plan.delete).to eq([])
      expect(plan.summary).to include("1 more surviving mutant not")
    end

    it "frees room by deleting the comments of survivors that are gone" do
      plan = described_class.plan(findings(finding("aabbccdd11223302"), finding("aabbccdd11223303")),
                                  existing: [posted("aabbccdd11223301", 1)], limit: 1)

      expect(plan.delete).to eq([1])
      expect(plan.post.map { |c| c[:digest] }).to eq(%w[aabbccdd11223302])
    end

    it "carries the full body, and reads findings that omit the truncation count" do
      one = finding("aabbccdd11223344")
      plan = described_class.plan({ "survivors" => [one] }, existing: [posted("aabbccdd11223355", 5)])

      expect(plan.post.first[:body]).to eq(described_class.body(one))
      expect(plan.delete).to eq([5])
    end

    it "accepts the limit as a string" do
      expect(described_class.plan(findings(finding("aabbccdd11223344")), limit: "1").post.size).to eq(1)
    end

    it "posts a comment on the first changed line of each live survivor" do
      plan = described_class.plan(findings(finding("aabbccdd11223344", line: 7)))

      expect(plan.post.map { |c| c.slice(:path, :line, :digest) })
        .to eq([{ path: "lib/x.rb", line: 7, digest: "aabbccdd11223344" }])
      expect(plan.delete).to eq([])
      expect(plan.summary).to be_nil
    end

    it "skips survivors off the diff, likely equivalent ones, arid ones and bad digests" do
      plan = described_class.plan(findings(finding("aabbccdd11223301", line: nil),
                                           finding("aabbccdd11223302", classification: "likely_equivalent"),
                                           finding("aabbccdd11223303", classification: "arid"),
                                           finding("not-a-digest"),
                                           finding("aabbccdd11223304", path: 5),
                                           finding("aabbccdd11223305")))

      expect(plan.post.map { |c| c[:digest] }).to eq(%w[aabbccdd11223305])
    end

    it "does not post a digest twice across pushes" do
      plan = described_class.plan(findings(finding("aabbccdd11223344"), finding("aabbccdd11223355")),
                                  existing: [posted("aabbccdd11223344", 9)])

      expect(plan.post.map { |c| c[:digest] }).to eq(%w[aabbccdd11223355])
      expect(plan.delete).to eq([])
    end

    it "deletes the comment of a survivor that is gone" do
      plan = described_class.plan(findings(finding("aabbccdd11223355")),
                                  existing: [posted("aabbccdd11223344", 9), { "id" => 4, "body" => "human note" }])

      expect(plan.delete).to eq([9])
    end

    it "keeps a still-live survivor's comment even when it is quiet now" do
      plan = described_class.plan(findings(finding("aabbccdd11223344", classification: "arid")),
                                  existing: [posted("aabbccdd11223344", 9)])

      expect(plan.delete).to eq([])
    end

    it "deletes nothing when the findings list was truncated" do
      plan = described_class.plan(findings(finding("aabbccdd11223355"), truncated: 3),
                                  existing: [posted("aabbccdd11223344", 9)])

      expect(plan.delete).to eq([])
    end

    it "caps posted plus kept comments and says how many were left out" do
      found = (1..4).map { |n| finding(format("aabbccdd1122330%d", n)) }
      plan = described_class.plan(findings(*found, truncated: 2), existing: [posted("aabbccdd11223301", 9)],
                                                                  limit: 2, run_url: "https://github.com/o/r/actions/runs/1")

      expect(plan.post.map { |c| c[:digest] }).to eq(%w[aabbccdd11223302])
      expect(plan.summary).to eq("#{described_class::SUMMARY_MARKER}\n4 more surviving mutants not shown as " \
                                 "comments. Full report: https://github.com/o/r/actions/runs/1")
    end

    it "uses a singular summary without a run link, and posts nothing at limit 0" do
      plan = described_class.plan(findings(finding("aabbccdd11223344")), limit: 0)

      expect(plan.post).to eq([])
      expect(plan.summary).to eq("#{described_class::SUMMARY_MARKER}\n1 more surviving mutant not shown as comments.")
    end

    it "treats a negative limit as zero and defaults to ten" do
      expect(described_class.plan(findings(finding("aabbccdd11223344")), limit: -3).post).to eq([])
      many = (10..21).map { |n| finding("aabbccdd112233#{n}") }
      expect(described_class.plan(findings(*many)).post.size).to eq(10)
    end
  end
end
