# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/limits"

RSpec.describe Checker do
  it "rejects amounts below the minimum and accepts the minimum itself" do
    expect(described_class.ok?(99)).to be(false)
    expect(described_class.ok?(100)).to be(true)
  end

  it "checks the maximum through the late-bound lambda" do
    expect(described_class.late_ok?(500)).to be(true)
    expect(described_class.late_ok?(10_000)).to be(true)
    expect(described_class.late_ok?(10_001)).to be(false)
  end
end
