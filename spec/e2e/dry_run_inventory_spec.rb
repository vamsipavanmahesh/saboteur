# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Models the README "A plan before the run" claim: `--dry-run --format json`
# prints the versioned mutant inventory - every planned mutant with its
# stable digest and edits - without booting the suite. The fixture carries a
# spec file that raises when loaded, so a booted suite would fail the run.
RSpec.describe "run --dry-run --format json inventory (end to end)", :e2e do
  it "prints the versioned inventory with digests and edits, and never loads a spec" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "spec", "explodes_on_load_spec.rb"),
               'raise "the suite was booted"\n')
    run = saboteur(dir, "--dry-run", "--format", "json")
    expect(run.status).to eq(0), run.err
    inventory = JSON.parse(run.out)
    expect(inventory.fetch("mode")).to eq("dry-run")
    expect(inventory.fetch("schema_version")).to eq(1)
    mutants = inventory.fetch("mutants")
    expect(mutants).not_to be_empty
    mutants.each do |mutant|
      expect(mutant.fetch("digest")).to match(/\A[0-9a-f]{16}\z/)
      expect(mutant.fetch("edits")).not_to be_empty
    end
    expect(File).not_to exist(File.join(dir, ".saboteur", "report.json"))
  end
end
