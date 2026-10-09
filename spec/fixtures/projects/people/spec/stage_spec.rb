# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/stage"

RSpec.describe Stage do
  it("is adult at 40") { expect(described_class.for(40)).to eq("adult") }
end
