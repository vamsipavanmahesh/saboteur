# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Locks review issue #125: an example that only passes after another one ran
# fails alone, so its "kill" is bogus. The unchanged-method check must catch it
# and report an error, never a kill.
RSpec.describe "order-dependent examples (end to end)", :e2e do
  let(:run) { saboteur(copy_fixture("orderdep")) }
  let(:dependent) { mutants(run).select { |m| m.dig("location", "start", "line") == 10 } }

  it "does not count kills by an order-dependent example" do
    expect(dependent).not_to be_empty
    expect(dependent.map { |m| m["status"] }.uniq).to eq(["RuntimeError"])
    expect(dependent.map { |m| m["statusReason"] }.uniq.first).to match(/also fails with the method unchanged/)
    expect(run.out).to include("kills rejected by unchanged-method check: #{dependent.size}")
    expect(run.out).to match(/Ordered#dependent_value: \d+ verdict\(s\) failed with the method unchanged/)
  end

  it "still kills mutants of the method whose example does not depend on order" do
    independent = mutants(run).select { |m| m.dig("location", "start", "line") == 6 }
    expect(independent.map { |m| m["status"] }.uniq).to eq(["Killed"])
  end

  it "never lets bogus kills pass as a green run" do
    expect(run.status).to eq(3)
    expect(run.err).to include("mutants errored")
  end
end
