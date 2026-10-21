# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Locks review issue #125 and its defined-order rescue (#557): an example
# that only passes after another one ran fails alone, so its "kill" is bogus.
# The scheduler retries such a kill with the file's examples in defined
# order through the last covering example. When that prefix clears the
# unchanged method, the kill stands - with the prefix as the covering tests.
# When the state-up lives in another spec file, no prefix of the covering
# file can clear it, and the bogus kill still stays an error, never green.
RSpec.describe "order-dependent examples (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("orderdep")) }
  let(:dependent) { mutants(run).select { |m| m.dig("location", "start", "line") == 10 } }

  it "rescues order-dependent kills with the file's defined-order prefix" do
    expect(dependent).not_to be_empty
    expect(dependent.map { |m| m["status"] }.uniq).to eq(["Killed"])
    prefix = ["./spec/ordered_spec.rb[1:1]", "./spec/ordered_spec.rb[1:2]"]
    dependent.each do |mutant|
      expect(test_names(run, mutant.fetch("coveredBy"))).to eq(prefix)
    end
  end

  it "still kills mutants of the method whose example does not depend on order" do
    independent = mutants(run).select { |m| m.dig("location", "start", "line") == 6 }
    expect(independent.map { |m| m["status"] }.uniq).to eq(["Killed"])
  end

  it "reports a green run once the bogus kills are rescued" do
    expect(run.status).to eq(0)
  end

  it "keeps a bogus kill no prefix can rescue out of the green run" do
    cross = saboteur(copy_fixture("orderdep_crossfile"))
    cross_mutants = mutants(cross)
    expect(cross_mutants).not_to be_empty
    expect(cross_mutants.map { |m| m["status"] }.uniq).to eq(["RuntimeError"])
    expect(cross.status).to eq(3)
    expect(cross.err).to include("mutants errored")
    # README: an error-dominated run prints "Score: n/a", not a number.
    expect(cross.out).to include("Score: n/a (0 of 10 mutants scored, n/a of scored)")
  end
end
