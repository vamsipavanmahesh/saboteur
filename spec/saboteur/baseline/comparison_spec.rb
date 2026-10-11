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
end
