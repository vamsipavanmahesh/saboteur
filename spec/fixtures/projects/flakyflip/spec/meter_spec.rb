# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/meter"

# Order-dependent on purpose: the second example reads state the first one
# drives. Mutant children fork from a parent that loaded but never ran the
# suite, so @reading starts nil there; a reordered confirmation run
# (--flaky-check) reads that nil where the primary run read 50.
RSpec.describe Meter do
  it "stores a mid-range reading" do
    Meter.reading = 50
    Meter.over?
    expect(Meter.reading).to eq(50)
  end

  it "is not over the limit" do
    expect(Meter.over?).to be(false)
  end
end
