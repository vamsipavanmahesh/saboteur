# frozen_string_literal: true

require_relative "../lib/blocks"

RSpec.describe Plain do
  it "adds one" do
    expect(described_class.new.succ(1)).to eq(2)
  end
end

RSpec.describe Covered do
  it "doubles" do
    expect(described_class.new(4).doubled).to eq(8)
  end
end
