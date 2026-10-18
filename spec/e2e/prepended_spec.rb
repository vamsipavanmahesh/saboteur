# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "a suite that wraps the method in a before hook", :e2e do
  it "judges mutants normally because super still reaches them (pod finding on #597)" do
    run = saboteur(copy_fixture("prepended"))
    list = mutants(run)
    expect(list).not_to be_empty
    expect(list.map { |m| m["status"] } - %w[Killed Survived]).to be_empty, other_outcomes(run)
    expect(list.map { |m| m["status"] }).to include("Killed")
    expect(run.out + run.err).not_to include("replaced the definition while they ran")
  end
end
