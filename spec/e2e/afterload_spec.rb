# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "a suite that re-loads the mutated file in an after hook", :e2e do
  it "keeps the honest verdict because the mutant did run (pod round 2 on #597)" do
    run = saboteur(copy_fixture("afterload"))
    list = mutants(run)
    expect(list).not_to be_empty
    expect(list.map { |m| m["status"] } - %w[Killed Survived]).to be_empty, other_outcomes(run)
    expect(list.map { |m| m["status"] }).to include("Survived")
    expect(run.out + run.err).not_to include("replaced the definition while they ran")
  end
end
