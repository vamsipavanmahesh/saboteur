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
