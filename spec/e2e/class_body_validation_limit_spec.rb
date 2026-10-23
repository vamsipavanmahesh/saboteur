# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Models the Chatwoot 7fe41fe static finding: class-body validates options
# contribute no mutants even when the validation itself has real tests.
# ActiveModel supplies the actual Rails validation DSL without a database.
RSpec.describe "class-body validation limit (end to end)", :e2e do
  it "mutates the ordinary method, but not the class-body validation options" do
    run = saboteur(copy_fixture("validation_dsl"), "--all")
    expect(run.status).to eq(0), other_outcomes(run)
    found = mutants(run)
    expect(found).not_to be_empty
    expect(found.map { |mutant| mutant.dig("location", "start", "line") }.uniq).to eq([11])
    expect(found.map { |mutant| mutant["status"] }.uniq).to eq(["Killed"])
  end
end
