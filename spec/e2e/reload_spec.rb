# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "a suite that re-loads the mutated file in a before hook", :e2e do
  it "marks the mutants unreachable instead of survived (issue #597)" do
    run = saboteur(copy_fixture("reload"))
    # Nothing was verified, so the run must not go silently green (#597).
    expect(run.status).to eq(3), run.err
    list = mutants(run)
    expect(list).not_to be_empty
    expect(list.map { |m| m["status"] }.uniq).to eq(["Ignored"])
    expect(list.map { |m| m["statusReason"] }.uniq.first)
      .to match(/replaced the definition while they ran.*widget\.rb/)
    expect(run.out).to include("Unreachable (out of the score):")
  end
end
