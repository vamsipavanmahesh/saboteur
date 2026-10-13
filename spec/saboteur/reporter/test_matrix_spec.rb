# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Reporter::TestMatrix do
  def result(status, killed_by:, covered_by:, replacement: ">")
    result_for(status, replacement:, killed_by:, covered_by:)
  end

  let(:results) do
    [
      result(:killed, killed_by: %w[a b], covered_by: %w[a b c], replacement: ">"),
      result(:killed, killed_by: %w[a], covered_by: %w[a b c], replacement: "<="),
      result(:survived, killed_by: [], covered_by: %w[a b c d], replacement: "<")
    ]
  end

  subject(:matrix) { described_class.new(results) }

  it "lists every test that covered an executed mutant" do
    expect(matrix.tests).to eq(%w[a b c d])
    expect(matrix.mutants_covered("a")).to eq(3)
    expect(matrix.mutants_covered("d")).to eq(1)
  end

  it "calls a test blind when it covered mutants and killed none" do
    expect(matrix.blind).to eq(%w[c d])
  end

  it "calls a test redundant only when every mutant it killed had another killer" do
    expect(matrix.redundant).to eq(%w[b])
    expect(matrix.redundant).not_to include("a")
    expect(matrix.mutants_killed("a")).to eq(2)
  end

  it "ignores errors, skips and timeouts: only killed and survived mutants count" do
    ignored = [result(:error, killed_by: [], covered_by: %w[x]), result(:timeout, killed_by: [], covered_by: %w[x])]
    expect(described_class.new(ignored).tests).to be_empty
  end

  it "does not count a killer the mutant was not covered by" do
    odd = [result(:killed, killed_by: %w[stranger], covered_by: %w[a])]
    expect(described_class.new(odd).blind).to eq(%w[a])
  end

  it "has no blind or redundant tests for an empty run" do
    empty = described_class.new([])
    expect([empty.tests, empty.blind, empty.redundant]).to all(be_empty)
  end
end
