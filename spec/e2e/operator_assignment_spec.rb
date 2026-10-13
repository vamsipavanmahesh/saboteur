# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "extended compound assignment operator (end to end)", :e2e do
  it "adds two candidates and exposes the missing nonzero assertion" do
    run = saboteur(copy_fixture("assignments"))
    expect(run.status).to eq(1), run.err
    expect(mutants(run).size).to eq(2)
    expect(mutants(run).map { |mutant| mutant["mutatorName"] }.uniq).to eq(["operator_assignment"])
    expect(mutants(run).map { |mutant| mutant["status"] }.sort).to eq(%w[Killed Survived])
  end
  it "honors cap and repeats stable digests" do
    dir = copy_fixture("assignments")
    path = File.join(dir, "lib", "assignments.rb")
    File.write(path, File.read(path).sub("value += 1", "value += 1; value *= 1"))
    config = File.join(dir, "config", "saboteur.rb")
    File.write(config, File.read(config).sub("c.operators", "c.max_mutants_per_method = 1; c.operators"))
    first = saboteur(dir)
    second = saboteur(dir)
    expect(mutants(first).size).to eq(2)
    expect(mutants(first).map { |m| m["id"] }).to eq(mutants(second).map { |m| m["id"] })
    expect(first.out).to include("max_mutants_per_method (1)")
  end
end
