# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "only load-time method calls", :e2e do
  it "accepts boot-only evidence but does not mistake one-line definitions for calls" do
    run = saboteur(copy_fixture("onlyload"))
    expect(run.status).to eq(0), run.err
    expect(mutants(run)).to be_empty
    skipped = run.json.fetch("skippedSubjects").to_h { |entry| [entry.fetch("subject"), entry.fetch("reason")] }
    expect(skipped).to eq(
      "BootValues.called" => Saboteur::Selection::CoverageMap::RAN_AT_LOAD,
      "BootValues.uncalled" => "no coverage",
      "BootValues.endless_called" => Saboteur::Selection::CoverageMap::RAN_AT_LOAD,
      "BootValues.endless_uncalled" => "no coverage"
    )
  end

  it "reports an all-load-only selection as incomplete in agent mode" do
    run = saboteur(copy_fixture("onlyload"), "--subject", "BootValues.called", "--agent")
    expect(run.status).to eq(3), run.err
    payload = JSON.parse(run.out)
    expect(payload).to include("verdict" => "incomplete", "exitCode" => 3)
    expect(payload.fetch("incomplete").map { |reason| reason.fetch("reason") }).to include("ran_at_load")
  end
end
