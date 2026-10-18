# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "a suite that raises on every warning", :e2e do
  it "never errors a mutant on the re-evaluation's own redefinition notice (issue #603)" do
    run = saboteur(copy_fixture("warnings"))
    # Genuine survivors keep their exit-1 verdict; nothing errors (#603).
    expect(run.status).to eq(1), run.err
    list = mutants(run)
    expect(list).not_to be_empty
    expect(list.map { |m| m["status"] } - %w[Killed Survived]).to be_empty, other_outcomes(run)
    expect(list.map { |m| m["status"] }).to include("Killed")
    # The fixture's own `def warn` override legitimately warns at boot;
    # what must never appear is a redefinition notice for the mutant's
    # method or a mutant erroring on it.
    expect(run.out + run.err).not_to match(/method redefined; discarding old reading/)
    expect(run.err).not_to include("mutants errored")
  end
end
