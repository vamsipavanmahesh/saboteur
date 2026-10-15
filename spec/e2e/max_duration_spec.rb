# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "--max-duration (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  it "stops the run at the budget, exits 4, and records what never ran (#245)" do
    run = saboteur(dir, "--all", "--max-duration", "1s")
    expect(run.status).to eq(4), run.err
    stop = run.json.fetch("earlyStop")
    expect(stop.fetch("reason")).to eq("max_duration")
    expect(stop.fetch("unreachedSubjects")).not_to be_empty
    expect(run.json.fetch("saboteur").fetch("exitCause")).to eq("budgetExhausted")
    expect(run.out).to include("stopped early (--max-duration spent):")
  end

  # The fixture has real survivors, so the plain verdict is 1: the point of
  # the flag is that the budget itself stops deciding the exit (no 4).
  it "treats an exhausted budget as non-failing with --max-duration-ok (#245)" do
    run = saboteur(dir, "--all", "--max-duration", "1s", "--max-duration-ok")
    expect(run.status).to eq(1), run.err
    expect(run.json.fetch("earlyStop").fetch("reason")).to eq("max_duration")
    expect(run.json.fetch("saboteur").fetch("exitCause")).to eq("survivors")
  end

  it "marks the agent summary partial when the budget stops the run (#245)" do
    run = saboteur(dir, "--all", "--max-duration", "1s", "--agent")
    payload = JSON.parse(run.out)
    expect(payload.fetch("status")).to eq("partial")
    expect(payload.fetch("incomplete")).to include(a_hash_including("reason" => "max_duration"))
    # Agent mode keeps its verdict-driven exitCode (survivors here); the
    # budget shows up in incomplete[] and earlyStop instead of exit 4.
    expect(run.status).to eq(1)
    expect(run.json.fetch("saboteur").fetch("exitCause")).to eq("budgetExhausted")
  end
end
