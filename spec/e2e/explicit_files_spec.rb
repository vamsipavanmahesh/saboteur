# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "saboteur run with explicit files and a threshold (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  def test_files(run)
    run.json.fetch("testFiles").keys
  end

  it "mutates the named source and runs only the named spec" do
    run = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb")
    expect(run.json.fetch("files").keys).to eq(["lib/people.rb"])
    expect(test_files(run)).to eq(["spec/person_spec.rb"])
    expect(mutants(run).map { |m| m["status"] }).to include("Killed")
  end

  it "accepts a directory of sources" do
    run = saboteur(dir, "lib", "--test", "spec/person_spec.rb", "--test", "spec/stage_spec.rb")
    expect(run.json.fetch("files").keys).to include("lib/people.rb", "lib/stage.rb")
  end

  it "builds a new coverage map when the selected tests change" do
    saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb")
    again = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb")
    other = saboteur(dir, "lib/people.rb", "--test", "spec/stage_spec.rb")
    expect(again.err).not_to include("building coverage map")
    expect(other.err).to include("building coverage map")
    expect(Dir.glob(File.join(dir, ".saboteur", "coverage-*.json")).size).to eq(2)
  end

  it "does not reuse verdicts from a run with other tests (--incremental)" do
    first = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb", "--incremental")
    second = saboteur(dir, "lib/people.rb", "--test", "spec/stage_spec.rb", "--incremental")
    expect(first.out).not_to include("reused")
    expect(second.out).not_to include("reused")
    expect(mutants(second).map { |m| m["status"] }).not_to include("Killed")
  end

  it "exits 2 without running when a source does not exist" do
    run = saboteur(dir, "lib/typo.rb", "--test", "spec/person_spec.rb")
    expect(run.status).to eq(2)
    expect(run.err).to include("source file not found: lib/typo.rb")
    expect(run.err).not_to include("building coverage map")
  end

  it "exits 2 when a test does not exist" do
    run = saboteur(dir, "lib/people.rb", "--test", "spec/typo_spec.rb")
    expect(run.status).to eq(2)
    expect(run.err).to include("test file not found: spec/typo_spec.rb; check the path or drop --test")
  end

  it "fails --threshold 100 while a mutant survives, and passes a score above a lower threshold" do
    failing = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb", "--threshold", "100")
    expect(failing.status).to eq(1), other_outcomes(failing)
    passing = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb", "--threshold", "1")
    expect(passing.status).to eq(0), other_outcomes(passing)
    expect(passing.out).to include("survived")
  end

  it "fails --threshold when no mutant was tested" do
    run = saboteur(dir, "lib/people.rb", "--test", "spec/stage_spec.rb", "--subject", "People::Person#describe",
                   "--threshold", "0")
    expect(run.status).to eq(1)
    expect(run.err).to include("no mutant was tested")
  end
end
