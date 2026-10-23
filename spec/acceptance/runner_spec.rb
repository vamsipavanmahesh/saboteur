# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

load File.expand_path("../../acceptance/runner.rb", __dir__)

# Guard specs for the checker's negative paths: an expectation key the
# runner does not understand must never pass silently, and a ranked label
# outside the maintainer's allowed set must fail.
RSpec.describe AcceptanceRunner do
  subject(:runner) { described_class.new(out: StringIO.new) }

  def run_with_mutants(mutant_list)
    AcceptanceRunner::RunResult.new(out: "", status: 1, json: { "files" => { "a.rb" => { "mutants" => mutant_list } } })
  end

  describe "mutant field checks" do
    let(:mutant) do
      { "id" => "abc123", "replacement" => "84", "status" => "Survived",
        "gapKind" => "number", "classification" => "assertion_gap", "valueDiffered" => true }
    end

    it "passes when the classification field matches" do
      want = { "match" => { "replacement" => "84" }, "status" => "Survived",
               "classification" => "assertion_gap", "valueDiffered" => true }
      expect(runner.send(:check_mutant, want, run_with_mutants([mutant]))).to eq([])
    end

    it "fails when the classification field differs - never silently skipped" do
      want = { "match" => { "replacement" => "84" }, "classification" => "assertion_gap" }
      problems = runner.send(:check_mutant, want, run_with_mutants([mutant.merge("classification" => "input_gap")]))
      expect(problems.length).to eq(1)
      expect(problems.first).to include('classification is "input_gap", expected "assertion_gap"')
    end
  end

  describe "ranked_top3 label sets" do
    let(:ranked) do
      [{ rank: 1, path: "lib/money/money/arithmetic.rb", line: 306, label: "boundary" },
       { rank: 2, path: "lib/money/money/arithmetic.rb", line: 42, label: "boundary" },
       { rank: 3, path: "lib/money/money/arithmetic.rb", line: 302, label: "boundary" }]
    end

    it "passes when the entry carries any label in the allowed set" do
      expect(runner.send(:check_ranked_top3, { "ranked_top3" => [{ "line" => 302, "label" => %w[boundary branch] }] },
                         ranked)).to eq([])
    end

    it "still passes with a scalar label" do
      expect(runner.send(:check_ranked_top3, { "ranked_top3" => [{ "line" => 302, "label" => "boundary" }] },
                         ranked)).to eq([])
    end

    it "fails a forbidden label (input_gap) even when the line is in the top 3" do
      forbidden = [ranked[0], ranked[1], ranked[2].merge(label: "input_gap")]
      want = { "ranked_top3" => [{ "line" => 302, "label" => %w[boundary branch] }] }
      problems = runner.send(:check_ranked_top3, want, forbidden)
      expect(problems.length).to eq(1)
      expect(problems.first).to include("labelled boundary or branch")
    end

    it "fails a forbidden label (coarse) even when the line is in the top 3" do
      forbidden = [ranked[0], ranked[1], ranked[2].merge(label: "coarse")]
      want = { "ranked_top3" => [{ "line" => 302, "label" => %w[boundary branch] }] }
      problems = runner.send(:check_ranked_top3, want, forbidden)
      expect(problems.length).to eq(1)
    end
  end
end
