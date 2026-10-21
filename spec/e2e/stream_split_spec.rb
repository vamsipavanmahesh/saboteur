# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "saboteur run stream split", :e2e do
  it "puts every progress byte on stderr and every finding on stdout" do
    run = saboteur(copy_fixture("people"), "--all", "--subject", "People::Person#adult?")
    expect(run.out).to include("Survivors (")
    expect(run.out).not_to include(".:killed", "eta ", "budget)")
    expect(run.err).to include(".:killed S:survived T:timeout E:error s:skipped L:resource limit")
    expect(run.err).not_to include("Survivors (", "score ")
  end
end
