# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::SurvivorGuidance do
  let(:entry) { %(i.mutation "abc123", subject: "Order#total", reason: "why it is equivalent") }

  it "wraps the ignore entry so it pastes into an ignore file as-is" do
    expect(described_class.ignore_block("abc123", "Order#total"))
      .to eq("Saboteur.ignore do |i|\n  #{entry}\nend")
  end

  it "carries the todo note on the entry line inside the block" do
    expect(described_class.ignore_block("abc123", "Order#total", todo: "fill in the subject"))
      .to eq("Saboteur.ignore do |i|\n  #{entry} # TODO: fill in the subject\nend")
  end
end
