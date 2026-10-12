# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "hazard guard and canary (issue #102)", :e2e do
  let(:dir) { copy_fixture("danger") }

  it "suppresses mutants inside the destructive call and leaves the tree intact" do
    run = saboteur(dir)
    expect(run.status).to eq(0)
    expect(run.out).to include("hazardous mutations suppressed")
    expect(File).to exist(File.join(dir, "SENTINEL.txt"))
    expect(File).to exist(File.join(dir, "lib", "builder.rb"))
    expect(File).to exist(File.join(dir, "spec", "builder_spec.rb"))
    expect(File).to exist(File.join(dir, "config", "saboteur.rb"))
  end

  it "aborts with exit 3 from the canary when hazardous mutants are allowed" do
    run = saboteur(dir, "--allow-hazardous")
    expect(run.status).to eq(3)
    expect(run.err).to include("canary")
    expect(run.err).to match(/[0-9a-f]{16}/)
  end

  it "fails fast in parallel: the canary trips on result arrival, not after the batch" do
    run = saboteur(dir, "--allow-hazardous", "--jobs", "2")
    expect(run.status).to eq(3)
    expect(run.err).to include("canary")
    expect(run.err).to match(/[0-9a-f]{16}/)
  end
end
