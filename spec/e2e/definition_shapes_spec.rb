# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Locks review issue #121: odd definition shapes are mutated and judged
# correctly, and a dead conditional definition is "no coverage", never a survivor.
RSpec.describe "definition shapes (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("shapes")) }

  def statuses_on(lines)
    mutants(run).select { |m| lines.cover?(m.dig("location", "start", "line")) }.map { |m| m["status"] }.uniq
  end

  it "finishes cleanly with no survivors and no odd outcomes" do
    expect(run.status).to eq(0), other_outcomes(run)
    expect(mutants(run).map { |m| m["status"] }.uniq).to eq(["Killed"])
  end

  it "mutates operator methods: +, unary minus, [] and ==" do
    expect(statuses_on(13..13)).to eq(["Killed"])
    expect(statuses_on(17..17)).to eq(["Killed"])
    expect(statuses_on(21..21)).to eq(["Killed"])
    expect(statuses_on(25..25)).to eq(["Killed"])
  end

  it "keeps two classes with the same method name apart" do
    expect(statuses_on(31..31)).to eq(["Killed"])
    expect(statuses_on(37..37)).to eq(["Killed"])
  end

  it "mutates a method in a compactly reopened class (class A::B)" do
    expect(statuses_on(56..56)).to eq(["Killed"])
  end

  it "reports the never-defined branch of a conditional def as no coverage, not as survivors" do
    expect(statuses_on(47..47)).to be_empty
    skipped = run.json.fetch("skippedSubjects").map(&:to_s)
    expect(skipped.join).to include("Shapes::Conditional#mode")
    expect(run.out).to include("1 subject not scored - no tests exist: Shapes::Conditional#mode")
    entry = run.json.fetch("skippedSubjects").find { |s| s["subject"] == "Shapes::Conditional#mode" }
    expect(entry.values_at("file", "line")).to eq(["lib/shapes.rb", 47])
  end
end
