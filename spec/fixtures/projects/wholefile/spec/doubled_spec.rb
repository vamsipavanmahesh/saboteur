# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/doubled"

RSpec.describe Doubled do
  it "adds two" do
    expect(described_class.new.replaced(1)).to eq(3)
  end

  it "triples" do
    expect(described_class.new.solo(2)).to eq(6)
  end
end
