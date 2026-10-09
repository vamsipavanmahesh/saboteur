# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/hazards"

RSpec.describe Hazards do
  let(:hazards) { described_class.new }

  it("spins") { expect(hazards.spin).to eq(:spun) }
  it("does not crash") { expect(hazards.crash_in_test).to eq(:fine) }
  it("loads") { expect(hazards.raise_on_load).to eq(:fine) }
  it("survives loading") { expect(hazards.die_on_load).to eq(:fine) }

  it "keeps its secret private" do
    expect(hazards.reveal).to eq(:secret)
    expect { hazards.secret }.to raise_error(NoMethodError, /private method/)
  end
end
