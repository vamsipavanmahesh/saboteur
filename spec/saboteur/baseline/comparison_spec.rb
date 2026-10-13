# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/baseline/comparison"

RSpec.describe Saboteur::Baseline::Comparison do
  let(:before) do
    { "compatibility" => { "scope" => "project" },
      "accepted" => [{ "id" => "a", "context" => "old", "reason" => "known gap" },
                     { "id" => "b", "context" => "old", "reason" => "gap" }],
      "candidates" => [{ "id" => "a", "status" => "survived", "context" => "old" },
                       { "id" => "b", "status" => "survived", "context" => "old" }] }
  end
  let(:current) { before.merge("complete" => true, "issues" => []) }

  def compare(candidates = current["candidates"], **changes)
    described_class.new(baseline: before,
                        current: current.merge("candidates" => candidates).merge(changes.transform_keys(&:to_s)))
  end

  it "passes complete compatible accepted survivors without changing their statuses" do
    result = compare
    expect(result.state).to eq("clean")
    expect(result.exit_code).to eq(0)
    expect(result.categories["accepted"].map { |entry| entry["id"] }).to eq(%w[a b])
    expect(result.categories.values.flatten.size).to eq(2)
  end

  it "separates new, changed, resolved kills, detected timeouts and unmatched entries" do
    candidates = [{ "id" => "c", "status" => "survived", "context" => "new" },
                  { "id" => "a", "status" => "survived", "context" => "changed" }]
    result = compare(candidates)
    expect(result.categories["new"].map { |entry| entry["id"] }).to eq(["c"])
    expect(result.categories["changed"].map { |entry| entry["id"] }).to eq(["a"])
    expect(result.categories["unmatched"].map { |entry| entry["id"] }).to eq(["b"])
    expect(result.state).to eq("review_required")
    expect(result.exit_code).to eq(1)
    resolved = compare([{ "id" => "b", "status" => "timeout" }, { "id" => "a", "status" => "killed",
                                                                  "kill_cause" => "assertion" }])
    expect(resolved.categories["resolved_kills"].map { |entry| entry["kill_cause"] }).to eq(["assertion"])
    expect(resolved.categories["detected_timeouts"].map { |entry| entry["id"] }).to eq(["b"])
    expect(resolved.exit_code).to eq(0)
  end

  it "fails incomplete evidence before any survivor count and retains independent errors" do
    candidate = { "id" => "a", "status" => "error", "reason" => "child exited" }
    result = compare([candidate], complete: false, issues: ["missing_result"])
    expect(result.state).to eq("incomplete")
    expect(result.exit_code).to eq(3)
    expect(result.issues).to eq(["missing_result"])
    expect(result.categories["errors"]).to eq([candidate])
    expect(result.categories["unmatched"].map { |entry| entry["id"] }).to eq(["b"])
    %w[error resource_limit skipped].each do |status|
      expect(compare([{ "id" => "a", "status" => status }]).exit_code).to eq(3)
    end
    expect(compare([], complete: true).exit_code).to eq(3)
    expect(compare(complete: false).exit_code).to eq(3)
    expect(compare(issues: ["changed_input"]).exit_code).to eq(3)
  end

  it "fails incompatible scopes without presenting unmatched entries as regressions" do
    result = compare(compatibility: { "scope" => "other" })
    expect(result.state).to eq("incompatible")
    expect(result.exit_code).to eq(2)
    expect(result.categories).to be_empty
  end

  it "orders findings by file, subject and ID and never treats ignore reasons as acceptance" do
    candidates = [{ "id" => "z", "status" => "survived", "identity" => [1, "b.rb", "A#m"], "ignored" => "yes" },
                  { "id" => "v", "status" => "survived", "identity" => [1, "a.rb", "B#m"] },
                  { "id" => "x", "status" => "survived", "identity" => [1, "a.rb", "A#m"] }]
    result = compare(candidates)
    expect(result.categories["new"].map { |entry| entry["id"] }).to eq(%w[x v z])
    expect(result.exit_code).to eq(1)
  end
  it "does not label unaccepted killed or timed-out new code as resolved acceptance" do
    result = compare(current["candidates"] + [{ "id" => "new-kill", "status" => "killed" },
                                              { "id" => "new-timeout", "status" => "timeout" }])
    expect(result.categories["resolved_kills"]).to be_empty
    expect(result.categories["detected_timeouts"]).to be_empty
    expect(result.exit_code).to eq(0)
  end

  describe "the score-drop gate (epsilon)" do
    def results(kills:, survivors:, timeouts: 0)
      Array.new(kills) { |index| { "id" => "k#{index}", "status" => "killed", "context" => "c" } } +
        Array.new(timeouts) { |index| { "id" => "t#{index}", "status" => "timeout", "context" => "c" } } +
        Array.new(survivors) { |index| { "id" => "s#{index}", "status" => "survived", "context" => "c" } }
    end

    def gate(before_entries, now_entries, epsilon)
      accepted = before_entries.select { |entry| entry["status"] == "survived" }
                               .map { |entry| entry.slice("id", "context").merge("reason" => "known") }
      described_class.new(baseline: before.merge("candidates" => before_entries, "accepted" => accepted),
                          current: { "compatibility" => before["compatibility"], "complete" => true,
                                     "issues" => [], "candidates" => now_entries },
                          epsilon: epsilon)
    end

    it "is off without an epsilon and reports no score" do
      result = gate(results(kills: 4, survivors: 1), results(kills: 1, survivors: 1), nil)
      expect(result.score).to be_nil
      expect(result.state).to eq("clean")
    end

    it "fails when removed kills lower the score by more than epsilon, with no survivor changed" do
      result = gate(results(kills: 4, survivors: 1), results(kills: 1, survivors: 1), 5.0)
      expect(result.categories["new"]).to be_empty
      expect(result.categories["unmatched"]).to be_empty
      expect(result.score).to eq("baseline" => 80.0, "current" => 50.0, "drop" => 30.0, "epsilon" => 5.0,
                                 "exceeded" => true)
      expect(result.state).to eq("review_required")
      expect(result.exit_code).to eq(1)
    end

    it "passes a drop of exactly epsilon and fails a drop just above it" do
      before_entries = results(kills: 3, survivors: 1)
      now_entries = results(kills: 1, survivors: 1)
      at_limit = gate(before_entries, now_entries, 25.0)
      expect(at_limit.score).to include("drop" => 25.0, "exceeded" => false)
      expect(at_limit.exit_code).to eq(0)
      expect(gate(before_entries, now_entries, 24.9).exit_code).to eq(1)
    end

    it "never fails a score that rose, and counts a timeout as a kill" do
      result = gate(results(kills: 1, survivors: 1), results(kills: 1, timeouts: 1, survivors: 1), 0.0)
      expect(result.score).to include("baseline" => 50.0, "exceeded" => false)
      expect(result.score["drop"]).to be_within(1e-9).of(-50.0 / 3)
      expect(result.score["current"]).to be_within(1e-9).of(200.0 / 3)
      expect(result.exit_code).to eq(0)
    end

    it "leaves incompatible baselines without a score" do
      incompatible = described_class.new(baseline: before.merge("candidates" => results(kills: 1, survivors: 0)),
                                         current: { "compatibility" => { "scope" => "other" }, "complete" => true,
                                                    "issues" => [], "candidates" => results(kills: 0, survivors: 1) },
                                         epsilon: 0.0)
      expect(incompatible.exit_code).to eq(2)
      expect(incompatible.score).to be_nil
    end

    it "reports no score when the fresh run scored nothing, and stays incomplete" do
      result = gate(results(kills: 4, survivors: 1), [{ "id" => "e", "status" => "error" }], 0.0)
      expect(result.score).to be_nil
      expect(result.exit_code).to eq(3)
    end

    it "keeps an incomplete run ahead of the score" do
      result = gate(results(kills: 4, survivors: 1), results(kills: 1, survivors: 1) +
                    [{ "id" => "e", "status" => "error" }], 0.0)
      expect(result.exit_code).to eq(3)
    end
  end
end
