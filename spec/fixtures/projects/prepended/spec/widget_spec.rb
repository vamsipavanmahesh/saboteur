# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/widget"

RSpec.describe Widget do
  # APM/memoize-style wrapper with no reload: the mutant still runs through
  # super, so its verdicts must be judged normally (pod finding on #597).
  before(:each) do
    Widget.prepend(Module.new do
      def price(quantity) = super
    end)
  end

  it "computes the price" do
    expect(described_class.new.price(3)).to eq(11)
    expect(described_class.new.price(0)).to eq(5)
  end
end
