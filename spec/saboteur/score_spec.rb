# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Score do
  def score_of(*results)
    described_class.of(results)
  end

  let(:half_and_half) do
    score_of(result_for(:killed, kill_cause: "assertion"),
             result_for(:killed, replacement: "<", kill_cause: "NoMethodError"))
  end

  it "scores 100 % with half of it from assertions and half from crashes" do
    expect([half_and_half.value, half_and_half.assertion_share, half_and_half.crash_share]).to eq([1.0, 0.5, 0.5])
  end

  # Triage states change exit behavior, never the number: every survived
  # result stays in the denominator (#155, #304).
  it "scores the same whatever the triage state, with todo still unignored" do
    accepted = result_for(:survived, replacement: "==")
    accepted.ignored = "equivalent"
    accepted.triage_state = "accepted_equivalent"
    wont_fix = result_for(:survived, replacement: "<")
    wont_fix.ignored = "legacy"
    wont_fix.triage_state = "wont_fix"
    todo = result_for(:survived, replacement: "!=")
    todo.triage_state = "todo"
    todo.triage_reason = "fix next sprint"
    killed = result_for(:killed)
    triaged = score_of(accepted, wont_fix, todo, killed)
    plain = score_of(result_for(:survived, replacement: "=="), result_for(:survived, replacement: "<"),
                     result_for(:survived, replacement: "!="), result_for(:killed))
    expect(triaged.value).to eq(plain.value)
    expect(report_of(accepted, wont_fix, todo).unignored_survivors).to eq([todo])
  end

  it "takes survivors into the denominator of every share" do
    score = score_of(result_for(:killed, kill_cause: "assertion"), result_for(:survived, replacement: "=="))
    expect([score.value, score.assertion_share, score.crash_share]).to eq([0.5, 0.5, 0.0])
  end

  it "counts timeouts as detected but neither assertion nor crash" do
    score = score_of(result_for(:killed, kill_cause: "assertion"), result_for(:timeout, replacement: "<"))
    expect([score.value, score.timeout_share, score.assertion_share]).to eq([1.0, 0.5, 0.5])
  end

  it "keeps kills with no recorded cause apart, so the parts still add up" do
    score = score_of(result_for(:killed), result_for(:killed, replacement: "<", kill_cause: "assertion"))
    expect([score.unclassified_share, score.assertion_share, score.value]).to eq([0.5, 0.5, 1.0])
  end

  it "has a split when the only recorded cause is a crash" do
    expect(score_of(result_for(:killed, kill_cause: "NoMethodError")).split_known?).to be(true)
  end

  it "has a split when the only recorded cause is an assertion" do
    expect(score_of(result_for(:killed, kill_cause: "assertion")).split_known?).to be(true)
  end

  it "has no split when no kill has a recorded cause" do
    expect(score_of(result_for(:killed)).split_known?).to be(false)
    expect(half_and_half.split_known?).to be(true)
  end

  it "leaves errors, resource limits and skips out" do
    score = score_of(result_for(:error), result_for(:resource_limit, replacement: "<"),
                     result_for(:skipped, replacement: "<=", reason: "no coverage"))
    expect([score.tested, score.value, score.assertion_share]).to eq([0, nil, nil])
  end

  it "exposes the numbers for the JSON report" do
    expect(half_and_half.to_h).to include(score: 1.0, assertionKills: 1, crashKills: 1, tested: 2)
  end
end
