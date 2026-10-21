# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/money_like"

RSpec.describe MoneyLike do
  it "adds two amounts" do
    expect((described_class.new(30) + described_class.new(12)).cents).to eq(42)
  end
end
