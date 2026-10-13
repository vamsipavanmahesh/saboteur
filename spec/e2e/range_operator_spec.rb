# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "extended range operator (end to end)", :e2e do
  it "adds two candidates and exposes the missing boundary assertion" do
    run = saboteur(copy_fixture("ranges"))
    expect(run.status).to eq(1), run.err
    expect(mutants(run).size).to eq(2)
    expect(mutants(run).map { |mutant| mutant["mutatorName"] }.uniq).to eq(["range"])
    expect(mutants(run).map { |mutant| mutant["status"] }.sort).to eq(%w[Killed Survived])
  end
  it "honors the per-method cap and keeps the same digest on repeated runs" do
    dir = copy_fixture("ranges")
    path = File.join(dir, "lib", "ranges.rb")
    File.write(path, File.read(path).sub("(1..3).cover?(value)", "[(1..3), (2..4)].any? { |r| r.cover?(value) }"))
    config = File.join(dir, "config", "saboteur.rb")
    File.write(config, File.read(config).sub("c.operators", "c.max_mutants_per_method = 1; c.operators"))
    first = saboteur(dir)
    second = saboteur(dir)
    expect(mutants(first).size).to eq(2)
    expect(mutants(first).map { |m| m["id"] }).to eq(mutants(second).map { |m| m["id"] })
    expect(first.out).to include("max_mutants_per_method (1)")
  end
end
