# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/hooks"

RSpec.describe Widget do
  it "tunes with a factor" do
    expect(described_class.tune(3)).to eq(6)
  end

  it "sizes boxes" do
    expect(described_class.new.size_of(5)).to eq("small")
    expect(described_class.new.size_of(10)).to eq("small")
    expect(described_class.new.size_of(11)).to eq("big")
  end
end
