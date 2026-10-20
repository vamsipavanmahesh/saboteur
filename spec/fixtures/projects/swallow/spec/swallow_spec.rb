# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/swallow"

RSpec.describe Consumer do
  it "returns the producer's value" do
    expect(described_class.new.safe_value).to eq(42)
  end

  it "falls back when the producer raises" do
    producer = instance_double(Producer)
    allow(producer).to receive(:value).and_raise(StandardError, "boom")
    allow(Producer).to receive(:new).and_return(producer)
    expect(described_class.new.safe_value).to eq(:fallback)
  end
end
