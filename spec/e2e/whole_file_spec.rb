# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "whole_file re-evaluation (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("wholefile")) }

  def statuses_on(line)
    mutants(run).select { |m| m.dig("location", "start", "line") == line }.map { |m| m["status"] }.uniq
  end

  it "judges a method by its tests, as the control: a single def is killed" do
    expect(statuses_on(14)).to eq(["Killed"])
  end

  it "mutates the definition that stays in place, and never reports the replaced one as a survivor" do
    expect(statuses_on(10)).to eq(["Killed"])
    expect(statuses_on(6)).to eq([])
    expect(mutants(run).map { |m| m["status"] }).not_to include("Survived")
    expect(run.out).to include("1 subject not scored - no tests exist: Doubled#replaced")
    entry = run.json.fetch("skippedSubjects").find { |s| s["subject"] == "Doubled#replaced" }
    expect(entry.values_at("file", "line")).to eq(["lib/doubled.rb", 5])
  end
end
