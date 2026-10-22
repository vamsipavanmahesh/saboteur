# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/meter"
RSpec.describe Meter do
  it "a sets reading" do
    Meter.reading = 50
    Meter.over?
  end
  it "b asserts" do
    expect(Meter.over?).to eq(false)
  end
end
