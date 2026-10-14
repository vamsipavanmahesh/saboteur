# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Locks the visibility matrix (issue #118): private, protected,
# `private :name`, `private def`, private_class_method, `class << self`,
# module_function and `extend self`. The fixture's specs never assert a
# method's value, only who may call it, so a body mutant survives exactly
# when re-evaluating the mutated method kept its visibility. Losing it would
# fail a visibility example and turn the mutant into a kill.
RSpec.describe "visibility matrix (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("visibility")) }
  let(:value_lines) do
    lines = File.readlines(File.join(run.dir, "lib", "visibility.rb"))
    lines.each_index.select { |index| lines[index].include?("SEED + 1") }.map(&:succ)
  end

  it "keeps all twelve hidden and public bodies re-evaluable with their visibility intact" do
    expect(run.status).to be <= 1, other_outcomes(run)
    expect(value_lines.size).to eq(12)
    arithmetic = mutants(run).select { |m| m["mutatorName"] == "arithmetic" }
    expect(arithmetic.map { |m| m.dig("location", "start", "line") }).to match_array(value_lines)
    expect(arithmetic.map { |m| m["status"] }.uniq).to eq(["Survived"])
  end

  it "ends every mutant as Killed or Survived, and only a raising body is killed" do
    killed = mutants(run).select { |m| m["status"] == "Killed" }
    expect(mutants(run).map { |m| m["status"] } - %w[Killed Survived]).to be_empty
    expect(killed.map { |m| m["mutatorName"] }.uniq)
      .to contain_exactly("body_raise", "argument_removal", "chain_removal")
    expect(mutants(run).size).to eq(68)
  end
end
