# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/fees"

RSpec.describe Fees do
  it "charges no fee for large amounts (typed)" do
    expect(described_class.new.typed_fee(999)).to eq(50)
    expect(described_class.new.typed_fee(1000)).to eq(50)
    expect(described_class.new.typed_fee(1001)).to eq(0)
  end

  it "charges no fee for large amounts (untyped)" do
    expect(described_class.new.untyped_fee(999)).to eq(50)
    expect(described_class.new.untyped_fee(1000)).to eq(50)
    expect(described_class.new.untyped_fee(1001)).to eq(0)
  end
end
