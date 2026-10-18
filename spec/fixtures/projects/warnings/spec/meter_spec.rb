# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Meter do
  it("discounts big readings") { expect(Meter.new.reading(120)).to eq(110) }
  it("keeps small readings")   { expect(Meter.new.reading(50)).to eq(50) }
end
