# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/ordered"

# These examples share state through a global, so the second one only passes
# when the first ran before it. Run alone it fails with or without a mutant.
RSpec.describe Ordered, order: :defined do
  it("prepares shared state") do
    $ordered_ready = true
    expect(described_class.new.setup_value).to eq(2)
  end

  it("depends on the example before it") do
    expect($ordered_ready).to be(true)
    expect(described_class.new.dependent_value).to eq(25)
  end
end
