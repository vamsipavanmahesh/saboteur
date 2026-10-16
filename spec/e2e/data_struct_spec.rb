# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Subjects defined in a constant-assigned Data.define or Struct.new block
# are mutated like any other subject: the constant names the generated
# class, so the mutant is re-evaluated on it (#290).
RSpec.describe "Data.define and Struct.new subjects", :e2e do
  let(:dir) { copy_fixture("datastruct") }

  it "mutates factory-block subjects instead of skipping them" do
    run = saboteur(dir, "--all")

    expect(run.status).to eq(0), other_outcomes(run)
    expect(run.out).to include("3 subjects")
    expect(run.out).not_to include("defined inside a block")
    expect(mutants(run).map { |m| m["status"] }.uniq).to eq(["Killed"])
  end
end
