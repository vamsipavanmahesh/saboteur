# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "heredoc and pattern coverage (end to end)", :e2e do
  it "runs whole-body replacements and pattern literals against their covering tests" do
    run = saboteur(copy_fixture("coverage_syntax"))
    expect(run.status).to be <= 1, other_outcomes(run)
    bodies = mutants(run).select { |mutant| %w[body_nil body_raise].include?(mutant["mutatorName"]) }
    expect(bodies.size).to eq(4)
    expect(bodies.map { |mutant| mutant["status"] }).to all(eq("Killed"))
    patterns = mutants(run).select { |mutant| mutant["mutatorName"] == "literal_string" }
    expect(patterns.size).to eq(2)
    expect(patterns.map { |mutant| mutant["status"] }).to all(eq("Killed"))
  end
end
