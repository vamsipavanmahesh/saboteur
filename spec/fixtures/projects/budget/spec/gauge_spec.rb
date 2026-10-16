# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/gauge"

RSpec.describe Gauge do
  it "labels a low level" do
    expect(Gauge.label(2)).to eq("low")
  end
end
