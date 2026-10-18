# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/widget"

RSpec.describe Widget do
  # Cleanup-reload shape (pod round 2 on #597): the test calls the mutant
  # first, the hook restores the file afterwards.
  after(:each) { load File.expand_path("../lib/widget.rb", __dir__) }

  it "returns an Integer" do
    expect(Widget.new.price(3)).to be_a(Integer)
  end
end
