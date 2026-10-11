# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "single-mutant replay", :e2e do
  let(:dir) { copy_fixture("people") }

  it "replays a fine mutant despite caps and incremental reuse, with the same selected tests" do
    original = saboteur(dir, "--subject", "People::Person#adult?")
    mutant = mutants(original).find { |item| !item["mutatorName"].start_with?("body_") }
    expect(mutant).not_to be_nil
    File.open(File.join(dir, ".saboteur.yml"), "a") { |file| file.puts "max_mutants_per_method: 1" }
    replay = saboteur(dir, "--id", mutant.fetch("id"), "--seed", "1", "--incremental", "--jobs", "2")
    expect(mutants(replay).size).to eq(1)
    actual = mutants(replay).first
    expect(actual.values_at("id", "status", "coveredBy")).to eq(mutant.values_at("id", "status", "coveredBy"))
    expect(replay.out).not_to include("reused")
    expect(File).not_to exist(File.join(dir, ".saboteur", "results.json"))
  end

  it "reports a missing digest without building coverage or writing a report" do
    replay = saboteur(dir, "--id", "0" * 16)
    expect(replay.status).to eq(2)
    expect(replay.err).to include("not found")
    expect(replay.json).to be_nil
    expect(replay.err).not_to include("building coverage map")
  end

  it "rejects a digest prefix" do
    replay = saboteur(dir, "--id", "abcd")
    expect(replay.status).to eq(2)
    expect(replay.err).to include("16 lowercase hexadecimal")
  end
end
