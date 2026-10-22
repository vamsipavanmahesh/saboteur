# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# D2: the gap-kind labels end to end - a surviving comparison mutant on
# covered code is observed never to change value, so the real binary labels
# it input_gap (#1290) and the JSON report keeps the boundary kind it replaced.
RSpec.describe "gap-kind labels (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  it "labels the comparison survivor input_gap and keeps the boundary kind in the output and report" do
    run = saboteur(dir, "--all")
    expect(run.status).to eq(1), run.err
    survivor = mutants(run).find { |m| m["mutatorName"] == "comparison" && m["status"] == "Survived" }
    expect(survivor.values_at("classification", "gapKind")).to eq(%w[input_gap boundary])
    expect(run.out).to include("[input_gap")
  end
end
