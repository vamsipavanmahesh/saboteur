# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Pins the wall time and every diagnostics-sourced field Engine#build_report
# hands to Report, and the evidence calls of #complete_evidence.
RSpec.describe Saboteur::Engine, "build_report pins" do
  let(:engine) { described_class.new(Saboteur::Config.new({}), err: StringIO.new) }
  let(:diagnostics) { engine.instance_variable_get(:@diagnostics) }

  it "measures the wall time from the given start to now" do
    allow(engine).to receive(:monotonic).and_return(142.5)
    expect(engine.send(:build_report, [], [], nil, 40.5).wall_time).to eq(102.0)
  end

  it "flows the diagnostics counters and collections into the report" do
    allow(diagnostics).to receive_messages(invalid_mutations: 7, warnings: ["w"],
                                           generation_events: ["g"], omissions: ["o"],
                                           hazard_suppressions: 3, inline_suppressions: ["i"],
                                           discovery_failures: ["d"], live_announced: ["l"])
    report = engine.send(:build_report, [], [], nil, engine.send(:monotonic))
    expect(report.invalid_mutations).to eq(7)
    expect(report.warnings).to eq(["w"])
    expect(report.generation_events).to eq(["g"])
    expect(report.omissions).to eq(["o"])
    expect(report.hazard_suppressions).to eq(3)
    expect(report.inline_suppressions).to eq(["i"])
    expect(report.discovery_failures).to eq(["d"])
    expect(report.live_announced).to eq(["l"])
  end

  it "flows the diff scope and operator policy into the report" do
    scope = Object.new
    report = engine.send(:build_report, [], [], scope, engine.send(:monotonic))
    expect(report.instance_variable_get(:@diff_scope)).to be(scope)
    expect(report.operator_policy).to eq(engine.config.operator_policy)
  end

  it "marks the report as a review exactly when a scope was given, and keeps the seed" do
    config = Saboteur::Config.new({ "seed" => 12_345 })
    engine = described_class.new(config, err: StringIO.new)
    scoped = engine.send(:build_report, [], [], Object.new, engine.send(:monotonic))
    expect(scoped.instance_variable_get(:@review)).to be(true)
    expect(scoped.seed).to eq(12_345)
    unscoped = engine.send(:build_report, [], [], nil, engine.send(:monotonic))
    expect(unscoped.instance_variable_get(:@review)).to be(false)
  end
end

RSpec.describe Saboteur::Engine, "complete_evidence pins" do
  let(:engine) { described_class.new(Saboteur::Config.new({}), err: StringIO.new) }
  let(:evidence) { instance_double(Saboteur::Baseline::RunEvidence) }

  before { engine.instance_variable_set(:@run_evidence, evidence) }

  it "plans every subject with an empty list when nothing was planned yet" do
    engine.instance_variable_set(:@evidence_planned, false)
    subjects = [Object.new, Object.new]
    allow(evidence).to receive(:finish).and_return(:done)
    expect(evidence).to receive(:plan).with(subjects, [[], []])
    expect(engine.send(:complete_evidence, [], subjects)).to eq(:done)
  end

  it "finishes the evidence with the diagnostics collections" do
    engine.instance_variable_set(:@evidence_planned, true)
    diagnostics = engine.instance_variable_get(:@diagnostics)
    allow(diagnostics).to receive_messages(generation_events: ["g"], omissions: ["o"],
                                           discovery_failures: ["d"], inline_suppressions: ["i"])
    expect(evidence).to receive(:finish)
      .with(results: [], stable_suite: false, skipped_subjects: {},
            generation_events: ["g"], omissions: ["o"],
            discovery_failures: ["d"], inline_suppressions: ["i"])
      .and_return(:done)
    expect(engine.send(:complete_evidence, [], [])).to eq(:done)
  end
end
