# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "branch coverage (end to end)", :e2e do
  it "reports untaken same-line arms as no coverage and keeps short-circuit behavior" do
    dir = copy_fixture("branches")
    2.times do
      run = saboteur(dir)
      expect(run.status).to eq(1), other_outcomes(run)
      literals = mutants(run).select { |mutant| mutant["mutatorName"] == "literal_number" }
      untaken = literals.select do |mutant|
        [3, 7].include?(mutant.dig("location", "start", "line")) && mutant["status"] == "NoCoverage"
      end
      expect(untaken.size).to eq(9)
      expect(untaken.map { |mutant| mutant["statusReason"] }).to all(eq("no coverage (branch not taken)"))
      both = literals.select { |mutant| mutant.dig("location", "start", "line") == 11 }
      expect(both.size).to eq(6)
      expect(both.map { |mutant| mutant["status"] }).to all(eq("Killed"))
      short = literals.select { |mutant| mutant.dig("location", "start", "line") == 15 }
      expect(short.size).to eq(3)
      expect(short.map { |mutant| mutant["status"] }).to all(eq("Survived"))
    end
  end
end
