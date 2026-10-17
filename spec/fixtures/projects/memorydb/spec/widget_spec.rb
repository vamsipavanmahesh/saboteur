# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Widget do
  it "doubles the number" do
    expect(described_class.create!(number: 21).double).to eq(42)
  end
end
