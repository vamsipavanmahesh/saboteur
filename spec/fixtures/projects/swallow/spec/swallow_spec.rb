# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/swallow"

RSpec.describe Consumer do
  it "returns the producer's value" do
    expect(described_class.new.safe_value).to eq(42)
  end
end
