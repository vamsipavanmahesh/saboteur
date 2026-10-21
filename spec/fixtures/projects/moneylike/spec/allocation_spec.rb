# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/allocation"

RSpec.describe Allocation do
  subject(:allocation) { described_class.new }

  it "splits an even amount" do
    expect(allocation.split(10, 2)).to eq(5)
  end

  it "splits an uneven amount down" do
    expect(allocation.split(9, 3)).to eq(3)
  end

  it "splits a large amount" do
    expect(allocation.split(100, 4)).to eq(25)
  end

  it "returns the amount for a single part" do
    expect(allocation.split(7, 1)).to eq(7)
  end

  it "leaves no remainder of nothing" do
    expect(allocation.remainder(0, 3)).to eq(0)
  end
end
