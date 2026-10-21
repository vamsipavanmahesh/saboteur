# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/widget"

RSpec.describe Widget do
  it "runs every method without looking at the results" do
    widget = described_class.new
    widget.one
    widget.two
    widget.three
    widget.four
    widget.five
    expect(widget).to be_a(described_class)
  end
end
