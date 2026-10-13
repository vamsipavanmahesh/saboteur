# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/endless_math"

RSpec.describe EndlessMath do
  it("doubles") { expect(described_class.new.double(3)).to eq(6) }
  it("doubles zero") { expect(described_class.new.double(0)).to eq(0) }
  it("negates") { expect(described_class.new.negate(3)).to eq(-3) }
  it("negates a negative") { expect(described_class.new.negate(-3)).to eq(3) }
end
