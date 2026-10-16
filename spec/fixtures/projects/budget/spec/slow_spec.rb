# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/gauge"

# Slow on purpose: one pass over this suite always costs more than the 1s
# budget in the --max-duration e2e, so the budget is spent before any
# subject starts - deterministically, on any machine speed.
RSpec.describe "slow pass" do
  it "takes three seconds" do
    sleep 3
    expect(Gauge.high?(20)).to eq(true)
  end
end
