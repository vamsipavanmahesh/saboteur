# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# D2: the gap-kind labels end to end - a surviving comparison mutant on
# covered code is classified boundary by the real binary, and the JSON
# report carries the new string.
RSpec.describe "gap-kind labels (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  it "classifies the surviving comparison mutant as boundary, in the output and the JSON report" do
    run = saboteur(dir, "--all")
    expect(run.status).to eq(1), run.err
    survivor = mutants(run).find { |m| m["mutatorName"] == "comparison" && m["status"] == "Survived" }
    expect(survivor["classification"]).to eq("boundary")
    expect(run.out).to include("[boundary")
  end
end
