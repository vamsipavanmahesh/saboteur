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

  # The fixture lives under the system temp dir, which the sandbox always
  # grants, so the destructive mutant really deletes - tracked files and
  # the run's own log. The hazard report must win over the log's absence:
  # exit 3, the canary naming the mutant as the likely cause, and never
  # the "killing test also fails" mislabel (#234).
  it "aborts with exit 3, the canary naming the culprit, when hazardous mutants are allowed" do
    run = saboteur(dir, "--allow-hazardous")
    expect(run.status).to eq(3)
    expect(run.err).to include("canary")
    expect(run.err).to match(/[0-9a-f]{16}/)
    expect(run.err).not_to include("killing test")
  end

  it "fails fast in parallel: the hazard report aborts the run, not just the subject" do
    run = saboteur(dir, "--allow-hazardous", "--jobs", "2")
    expect(run.status).to eq(3)
    expect(run.err).to include("canary")
    expect(run.err).to match(/[0-9a-f]{16}/)
    expect(run.err).not_to include("killing test")
  end

  # The logloss fixture's mutant deletes only the tool's own cache: tracked
  # files survive, the canary stays silent, and the runner's own check must
  # still stop the run with a tool error naming the mutant (#234).
  it "aborts with a tool error when only the tool's own files vanish" do
    run = saboteur(copy_fixture("logloss"), "--allow-hazardous")
    expect(run.status).to eq(3)
    expect(run.err).to include("vanished mid-run")
    expect(run.err).to match(/[0-9a-f]{16}/)
    expect(run.err).not_to include("killing test")
  end
end
