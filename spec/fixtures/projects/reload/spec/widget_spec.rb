# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/widget"

RSpec.describe Widget do
  # The rolify suite shape (issue #597): every example re-loads the source
  # file, silently replacing the mutant the child installed.
  before(:each) { load File.expand_path("../lib/widget.rb", __dir__) }

  it "computes the price" do
    expect(described_class.new.price(3)).to eq(11)
    expect(described_class.new.price(0)).to eq(5)
  end
end
