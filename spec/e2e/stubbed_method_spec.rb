# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# A method exercised only through a stub is never really executed: saboteur
# reports it as not scored instead of inventing mutants, and the rest of the
# suite still passes. The exact screen wording is being fixed in #1145; the
# structured report entry is the stable pin.
require "support/e2e_helpers"

RSpec.describe "a stubbed method", :e2e do
  include E2EHelpers

  it "is reported as not scored while the tested method passes" do
    dir = copy_fixture("stubbed")
    run = saboteur(dir)

    expect(run.status).to eq(0), run.out + run.err
    expect(mutants(run).map { |m| m["status"] }.uniq).to eq(["Killed"])

    skipped = run.json["skippedSubjects"].map { |s| [s["subject"], s["reason"]] }
    expect(skipped).to include(["Transfer#fx_rate", "no coverage"])
    expect(run.out).to include("Transfer#fx_rate")
  end
end
