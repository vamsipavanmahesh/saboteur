# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "--flaky-check disagreement (end to end)", :e2e do
  # Meter.over? keeps state in a class ivar: the 100->0 mutant is killed when
  # test "a" runs first and survives when "b" does, so the reordered rerun
  # disagrees with the first run (#1167).
  it "leaves the mutant unverified and exits 3 with its own reason, not a spent budget" do
    run = saboteur(copy_fixture("flaky_order"), "--all", "--flaky-check", "survivors")
    expect(run.status).to eq(3), run.err
    expect(run.out).not_to include("--max-duration")
    expect(run.err).to match(/changed verdict on the --flaky-check reordered rerun/)
    expect(run.json.fetch("saboteur").fetch("exitCause")).to eq("incomplete")
    expect(run.json["earlyStop"]).to be_nil
  end
end
