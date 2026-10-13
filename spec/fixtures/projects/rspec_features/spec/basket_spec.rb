# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/basket"

RSpec.shared_examples "a priced basket" do |expected_total|
  it "adds the prices" do
    expect(basket.total).to eq(expected_total)
  end
end

RSpec.describe Basket do
  describe "with items" do
    let(:basket) { described_class.new([40, 60, 30]) }

    it_behaves_like "a priced basket", 130

    it "checks several things at once", :aggregate_failures do
      expect(basket.empty?).to be(false)
      expect(basket.expensive?).to be(true)
      expect(basket.discounted(10)).to eq(117)
    end
  end

  describe "when empty" do
    let(:basket) { described_class.new([]) }

    it_behaves_like "a priced basket", 0

    it "is empty and not expensive", :aggregate_failures do
      expect(basket.empty?).to be(true)
      expect(basket.expensive?).to be(false)
    end
  end

  it "does not charge tax yet" do
    pending "tax is not implemented"
    expect(described_class.new([10]).total).to eq(11)
  end
end
