# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Shared examples, aggregate_failures, pending examples and a configured
# example_status_persistence_file_path must all work under saboteur, and the
# user's persistence file must be left exactly as it was.
RSpec.describe "RSpec features (end to end)", :e2e do
  let(:dir) { copy_fixture("rspec_features") }
  let(:persistence_file) { File.join(dir, "spec", "examples.txt") }

  it "runs, kills mutants through shared examples and aggregate_failures, and leaves the persistence file alone" do
    before = File.binread(persistence_file)
    modified = File.mtime(persistence_file)
    run = saboteur(dir)
    expect(run.status).to be <= 1, other_outcomes(run)
    expect(run.json.fetch("skippedSubjects")).to be_empty
    statuses = mutants(run).map { |m| m["status"] }
    expect(statuses).to include("Killed")
    expect(statuses - %w[Killed Survived]).to be_empty, other_outcomes(run)
    expect(File.binread(persistence_file)).to eq(before)
    expect(File.mtime(persistence_file)).to eq(modified)
  end

  it "treats the pending example as pending, not as a failure of the unchanged suite" do
    run = saboteur(dir)
    expect(run.err).not_to match(/baseline.*fail|unchanged suite.*fail/i)
    expect(run.status).not_to eq(3), other_outcomes(run)
  end
end
