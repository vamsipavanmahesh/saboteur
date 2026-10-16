# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/rules"

RSpec.describe Rules do
  it "requires a city" do
    expect(described_class.rule_for(:city)).to eq("required")
  end

  it "marks a zip optional" do
    expect(described_class.rule_for(:zip)).to eq("optional")
  end

  it "knows the alpha tag" do
    expect(described_class.tagged?("alpha")).to be(true)
  end
end
