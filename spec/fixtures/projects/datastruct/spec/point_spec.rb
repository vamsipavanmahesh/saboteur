# frozen_string_literal: true

require_relative "../lib/point"

RSpec.describe Point do
  it "compares coordinates, including the boundary" do
    expect(described_class.new(1, 2).above?).to be(true)
    expect(described_class.new(2, 1).above?).to be(false)
    expect(described_class.new(1, 1).above?).to be(false)
  end

  it "builds the origin" do
    expect(described_class.origin).to eq(described_class.new(0, 0))
  end
end
