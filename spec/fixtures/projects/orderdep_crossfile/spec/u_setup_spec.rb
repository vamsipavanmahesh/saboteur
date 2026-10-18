# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/cross"

# Runs first under the fixture's pinned seed. It never calls
# Cross#dependent_value, so it is not a covering test for it - and no
# defined-order prefix of the covering file can include it.
RSpec.describe "cross-file setup" do
  it("prepares shared state") do
    $cross_ready = true
    expect(1 + 1).to eq(2)
  end
end
