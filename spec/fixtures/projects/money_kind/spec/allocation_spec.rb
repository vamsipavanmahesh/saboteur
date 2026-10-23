# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "bigdecimal"
require_relative "../lib/money/money/allocation"

# Pins exact allocations for positive integer parts only: the parts_sum > 0
# comparison is probed, and the `>=`/`!=` mutants keep the pinned result, so
# they survive as an observed input gap (#1314).
RSpec.describe Money::Allocation do
  it "splits proportionally" do
    expect(described_class.generate(100, [30, 70])).to eq([30, 70])
  end

  it "gives the remainder to the last parts" do
    expect(described_class.generate(5, [1, 1, 1])).to eq([2, 2, 1])
  end
end
