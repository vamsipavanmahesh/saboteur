# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/person"

RSpec.describe Person do
  it "is not above the limit" do
    expect(described_class.new.check).to be(false)
  end
end
