# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::MutationSource::OperatorExamples do
  let(:registry) { Saboteur::MutationSource::OperatorRegistry }

  it "has exactly one example for every public operator name" do
    expect(described_class::EXAMPLES.keys).to match_array(registry::DESCRIPTIONS.keys)
  end

  it "writes each example as original -> mutated, and the two differ" do
    described_class::EXAMPLES.each do |name, example|
      original, mutated = example.split(" -> ", 2)
      expect(mutated).not_to be_nil, name
      expect(original).not_to eq(mutated), name
    end
  end

  it "is what --list-operators prints after each description" do
    out = StringIO.new
    registry.list(out)
    expect(out.string.lines.size).to eq(described_class::EXAMPLES.size)
    expect(out.string).to include("comparison  on  ", "  a < b -> a <= b\n")
  end
end
