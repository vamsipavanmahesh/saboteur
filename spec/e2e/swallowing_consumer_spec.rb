# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Locks the second half of review issue #129. The first half, a mutant that
# loops forever times out and its grandchild is killed, is already locked by
# the "hazardous mutants" examples in phase1_spec.rb.
RSpec.describe "a consumer that swallows StandardError (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("swallow")) }

  it "still kills the whole-body raise mutant of the producer, by the real answer it changes" do
    expect(run.status).to eq(0), other_outcomes(run)
    raise_mutant = mutants(run).find { |m| m["mutatorName"] == "body_raise" && m.dig("location", "start", "line") == 6 }
    expect(raise_mutant["status"]).to eq("Killed")
    expect(raise_mutant["statusReason"]).to eq("assertion")
  end

  it "leaves no survivors in the producer or the consumer" do
    expect(mutants(run).map { |m| m["status"] }.uniq).to eq(["Killed"])
  end
end
