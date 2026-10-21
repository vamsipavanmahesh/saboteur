# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# #1167: a --flaky-check survivors confirmation rerun that disagrees makes
# the verdict unverified - out of the score - and the run must say so
# honestly: exit 3 ("the change is unverified"), never exit 4 with
# "--max-duration spent" when no budget was set.
require "support/e2e_helpers"

RSpec.describe "--flaky-check survivors", :e2e do
  include E2EHelpers

  it "marks a disagreed verdict unverified and exits 3, not a phantom budget stop (#1167)" do
    dir = copy_fixture("flakyflip")
    run = saboteur(dir, "--flaky-check", "survivors")

    flipped = mutants(run).find { |m| m["status"] == "Ignored" }
    expect(flipped).not_to be_nil
    expect(flipped["statusReason"]).to include("flaky verdict: first survived, then killed")

    expect(run.out).to include("unverified: Meter.over?")
    expect(run.out).not_to include("--max-duration spent")
    expect(run.status).to eq(3)
  end
end
