# frozen_string_literal: true

require_relative "../lib/deep"

RSpec.describe Deep do
  it "returns the value" do
    expect(described_class.new.identity(1)).to eq(1)
  end
end
