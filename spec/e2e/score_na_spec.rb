# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# README ("A score that tells the truth"): "an error-dominated run prints
# `Score: n/a` instead of a number you would misread."
RSpec.describe "saboteur run on an error-dominated run (end to end)", :e2e do
  def headline(run)
    run.out.lines.map(&:chomp).find { |line| line.start_with?("Score:") }
  end

  it "prints Score: n/a with the scored count when most mutants errored" do
    run = saboteur(copy_fixture("hazards"), "--all")

    expect(run.status).to eq(3), other_outcomes(run)
    expect(headline(run)).to eq("Score: n/a (2 of 5 mutants scored, 100.0 % of scored)")
    expect(run.err).to include("3 of 5 mutants errored, so the run tested almost nothing")
  end

  it "prints Score: n/a with nothing scored when every mutant errored" do
    run = saboteur(copy_fixture("orderdep_crossfile"))

    expect(run.status).to eq(3), other_outcomes(run)
    expect(headline(run)).to eq("Score: n/a (0 of 10 mutants scored, n/a of scored)")
    expect(run.out).not_to match(/^Score: \d/)
  end

  it "keeps the numeric score on a run where errors are not the majority" do
    run = saboteur(copy_fixture("people"), "lib/people.rb", "--test", "spec/person_spec.rb")

    expect(headline(run)).to match(/\AScore: \d+\.\d%/)
    expect(run.err).not_to include("errored, so the run tested almost nothing")
  end
end
