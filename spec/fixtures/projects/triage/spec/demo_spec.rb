# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/demo"

RSpec.describe Demo do
  it "returns the value it logs" do
    allow($stdout).to receive(:puts)
    expect(described_class.new.noisy(3)).to eq(3)
  end

  it "classifies counts away from the limit" do
    expect(described_class.new.limit(3)).to eq(:small)
    expect(described_class.new.limit(30)).to eq(:big)
  end

  it "picks one" do
    expect(described_class.new.pick(true)).to eq(1)
  end

  it "reads a given name" do
    expect(described_class.new.fetch_name({ name: "x" })).to eq("x")
  end
end
