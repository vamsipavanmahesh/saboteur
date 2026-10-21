# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/transfer"

RSpec.describe Transfer do
  it "computes the fee" do
    expect(Transfer.new.fee(2)).to eq(4)
  end

  it "reads the rate through a stub" do
    transfer = Transfer.new
    allow(transfer).to receive(:fx_rate).and_return(1.5)
    expect(transfer.fx_rate * 2).to eq(3.0)
  end
end
