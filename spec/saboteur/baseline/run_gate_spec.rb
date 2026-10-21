# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/baseline/run_gate"

RSpec.describe Saboteur::Baseline::RunGate do
  def candidates(detected, survived)
    (1..detected).map { |n| { "id" => "k#{n}", "status" => "killed" } } +
      (1..survived).map { |n| { "id" => "s#{n}", "status" => "survived", "context" => "c" } }
  end

  def gate(before:, now:, epsilon: nil, complete: true)
    manifest = instance_double(Saboteur::Baseline::Manifest,
                               compatibility: { "scope" => "project" },
                               accepted: before.select { |e| e["status"] == "survived" }
                                               .to_h { |e| [e["id"], e.merge("reason" => "known")] },
                               candidates: before.to_h { |e| [e["id"], e] })
    report = instance_double(Saboteur::Report,
                             run_evidence: { "compatibility" => { "scope" => "project" },
                                             "candidates" => now, "complete" => complete, "issues" => [] })
    described_class.build(manifest:, report:, epsilon:)
  end

  it "passes when every survivor was accepted in the baseline, compatible and complete" do
    before = candidates(3, 2)
    result = gate(before:, now: before)
    expect(result).not_to be_failed
    expect(result).not_to be_incompatible
    expect(result).not_to be_incomplete
  end

  it "fails on a new survivor and names it by digest" do
    before = candidates(3, 1)
    now = before + [{ "id" => "s9", "status" => "survived", "context" => "c" }]
    result = gate(before:, now:)
    expect(result).to be_failed
    expect(result.new_survivor_ids).to eq(["s9"])
  end

  it "passes when a baseline survivor was fixed and none is new" do
    before = candidates(3, 1)
    expect(gate(before:, now: candidates(4, 0))).not_to be_failed
  end

  it "fails a score drop beyond epsilon, comparing decimals a rounded string would miss" do
    before = candidates(1229, 771)
    # Four killed mutants are gone (deleted code), no survivor is new:
    # 1225/1996 = 61.37% vs 61.45% - a 0.08-point drop both sides round to "61%".
    now = candidates(1225, 771)
    expect(gate(before:, now:, epsilon: 0.05)).to be_failed
    expect(gate(before:, now:, epsilon: 0.1)).not_to be_failed
  end

  it "has no score gate without an epsilon" do
    expect(gate(before: candidates(3, 1), now: candidates(2, 1)).score_exceeded?).to be(false)
  end

  it "is incompatible when the run's inputs differ from the baseline's" do
    manifest = instance_double(Saboteur::Baseline::Manifest,
                               compatibility: { "scope" => "other" },
                               accepted: {}, candidates: { "s1" => { "id" => "s1", "status" => "survived" } })
    report = instance_double(Saboteur::Report,
                             run_evidence: { "compatibility" => { "scope" => "project" },
                                             "candidates" => [{ "id" => "s1", "status" => "survived" }],
                                             "complete" => true, "issues" => [] })
    result = described_class.build(manifest:, report:)
    expect(result).to be_incompatible
    expect(result).not_to be_incomplete
  end

  it "is incomplete when the run's evidence is incomplete" do
    before = candidates(3, 1)
    result = gate(before:, now: before, complete: false)
    expect(result).to be_incomplete
    expect(result).not_to be_incompatible
  end

  it "refuses a report without execution evidence" do
    manifest = instance_double(Saboteur::Baseline::Manifest, compatibility: {}, accepted: {}, candidates: {})
    report = instance_double(Saboteur::Report, run_evidence: nil)
    expect { described_class.build(manifest:, report:) }.to raise_error(Saboteur::Error, /execution evidence/)
  end
end
