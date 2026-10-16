# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "--max-duration (end to end)", :e2e do
  # The budget fixture's suite always costs ~3s a pass, so a 1s budget is
  # spent during the first baseline check on any machine: boot, baselines
  # and the coverage map all count (#245), and the run stops before any
  # subject - deterministically.
  let(:dir) { copy_fixture("budget") }

  it "stops the run at the budget, exits 4, and records what never ran (#245)" do
    run = saboteur(dir, "--all", "--max-duration", "1s")
    expect(run.status).to eq(4), run.err
    stop = run.json.fetch("earlyStop")
    expect(stop.fetch("reason")).to eq("max_duration")
    expect(stop.fetch("unreachedSubjects")).to contain_exactly("Gauge.high?", "Gauge.label")
    expect(run.json.fetch("saboteur").fetch("exitCause")).to eq("budgetExhausted")
    expect(run.out).to include("stopped early (--max-duration spent):")
  end

  # --max-duration-ok leaves the exit to the verdict - and a run that
  # tested nothing has no verdict to pass: exit 3, not 0 (the budget
  # itself is still not the decider: no 4).
  it "leaves the exit to the verdict with --max-duration-ok, which fails a run that tested nothing (#245)" do
    run = saboteur(dir, "--all", "--max-duration", "1s", "--max-duration-ok")
    expect(run.status).to eq(3), run.err
    expect(run.json.fetch("earlyStop").fetch("reason")).to eq("max_duration")
    expect(run.json.fetch("saboteur").fetch("exitCause")).to eq("incomplete")
    expect(run.err).to include("no score to judge")
  end

  it "marks the agent summary partial when the budget stops the run (#245)" do
    run = saboteur(dir, "--all", "--max-duration", "1s", "--agent")
    payload = JSON.parse(run.out)
    expect(payload.fetch("status")).to eq("partial")
    expect(payload.fetch("incomplete")).to include(a_hash_including("reason" => "max_duration"))
    # Agent mode keeps its verdict-driven exit code (3: incomplete, as no
    # mutant ran); the budget shows up in incomplete[] and earlyStop
    # instead of exit 4.
    expect(run.status).to eq(3)
    expect(run.json.fetch("saboteur").fetch("exitCause")).to eq("budgetExhausted")
  end
end
