# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/boot_values"

RSpec.describe "boot values" do
  it "checks the cached values without calling any method" do
    expect(BOOT_VALUES).to eq([123, 789])
  end
end
