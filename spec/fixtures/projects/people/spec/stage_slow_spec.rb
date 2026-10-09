# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/stage"

# Defined first and slow on purpose: with fastest-first ordering the quick
# test in stage_spec.rb must be the one that kills mutants.
RSpec.describe "Stage (slow)" do
  it "is adult at 50, slowly" do
    sleep 0.3
    expect(Stage.for(50)).to eq("adult")
  end
end
