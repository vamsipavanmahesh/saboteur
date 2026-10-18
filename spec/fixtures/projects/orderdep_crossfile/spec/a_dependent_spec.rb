# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/cross"

# The dependent example only passes after u_setup_spec.rb ran. Its own file's
# defined-order prefix cannot set that state up, so the retry's unchanged run
# fails too and the bogus kill stays an error.
RSpec.describe Cross, order: :defined do
  it("runs alone just fine") do
    expect(2 + 2).to eq(4)
  end

  it("depends on the other file's example") do
    expect($cross_ready).to be(true)
    expect(described_class.new.dependent_value).to eq(25)
  end
end
