# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "candidate limits", :e2e do
  let(:dir) { copy_fixture("people") }

  it "caps each method separately, keeps coarse mutants first and repeats with the same digests" do
    File.write(File.join(dir, "config", "saboteur.rb"),
               "Saboteur.configure { |c| c.include = [\"lib/**/*.rb\"]; c.max_mutants_per_method = 2 }\n")
    first = saboteur(dir, "--all", "--subject", "People::Person#adult?", "--subject", "People::Person#describe")
    second = saboteur(dir, "--all", "--subject", "People::Person#adult?", "--subject", "People::Person#describe",
                      "--jobs", "2")
    expect(mutants(first).size).to eq(4)
    expect(mutants(first).map { |mutant| mutant["mutatorName"] }).to eq(%w[body_true body_false body_nil body_raise])
    expect(mutants(second).map { |mutant| mutant.values_at("id", "status") })
      .to eq(mutants(first).map { |mutant| mutant.values_at("id", "status") })
    expect(first.out).to include("max_mutants_per_method (2)")
  end

  it "reports an uncovered method as a skipped subject, not a mutant" do
    File.open(File.join(dir, "lib", "people.rb"), "a") do |file|
      file.puts "class Untested\n  def value\n    123\n  end\nend"
    end
    run = saboteur(dir, "--all", "--subject", "Untested")
    expect(run.status).to eq(0), run.err
    expect(mutants(run)).to be_empty
    expect(run.out).to include("1 subject, 0 mutants", "Not scored - no test executes these", "Untested#value",
                               "saboteur: 1 subject untested")
    expect(run.json["skippedSubjects"].first).to include("subject" => "Untested#value", "reason" => "no coverage")
  end
  it "keeps a one-line uncalled definition uncovered, without inventing mutants" do
    File.open(File.join(dir, "lib", "people.rb"), "a") do |file|
      file.puts "class LoadOnly; def value; 123; end; end"
    end
    run = saboteur(dir, "--all", "--subject", "LoadOnly")
    expect(run.status).to eq(0), run.err
    expect(mutants(run)).to be_empty
    expect(run.out).to include("1 subject, 0 mutants", "Not scored - no test executes these", "LoadOnly#value",
                               "saboteur: 1 subject untested")
    expect(run.json["skippedSubjects"].first).to include(
      "subject" => "LoadOnly#value", "reason" => "no coverage"
    )
  end
end
