# frozen_string_literal: true

require_relative "../lib/size"

RSpec.describe Size do
  it "compares width and height, including the boundary" do
    expect(described_class.new(2, 1).wide?).to be(true)
    expect(described_class.new(1, 2).wide?).to be(false)
    expect(described_class.new(1, 1).wide?).to be(false)
  end
end
