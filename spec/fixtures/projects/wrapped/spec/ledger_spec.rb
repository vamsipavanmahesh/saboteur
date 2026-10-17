# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/ledger"

RSpec.describe Ledger do
  it "records twice the amount" do
    ledger = Ledger.new
    ledger.record(3)
    expect(ledger.entries).to eq([6])
  end
end
