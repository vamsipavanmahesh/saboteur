# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Locks review issue #123: a spec that calls only the alias still kills mutants
# of the original, because the re-evaluator re-points aliases.
RSpec.describe "alias_method aliases (end to end)", :e2e do
  it "kills every mutant of the original method through its alias" do
    run = saboteur(copy_fixture("aliases"))
    expect(run.status).to eq(0), other_outcomes(run)
    expect(mutants(run)).not_to be_empty
    expect(mutants(run).map { |m| m["status"] }.uniq).to eq(["Killed"])
    expect(run.json.fetch("skippedSubjects")).to be_empty
  end
end
