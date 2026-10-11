# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/trivial_equivalence"

# rubocop:disable-next Metrics/BlockLength
RSpec.describe TrivialEquivalence::EquivalenceJudge do
  def verdict(original, mutated, level: :strict)
    described_class.new(level: level).judge(original_source: original, mutated_source: mutated, path: "sample.rb")
  end

  it "proves identical source equivalent" do
    expect(verdict("def a = 1\n", "def a = 1\n")).to be_proven_equivalent
  end

  it "proves a change inside source text that compiles to the same instructions" do
    expect(verdict("def a\n  x = 1\n  x\nend\n", "def a\n  x = 1 \n  x\nend\n")).to be_proven_equivalent
  end

  it "does not prove a changed literal equivalent" do
    expect(verdict("def a = 1\n", "def a = 2\n")).not_to be_proven_equivalent
  end

  it "does not prove a changed literal in a nested block equivalent" do
    original = "def a = [1].map { |v| v + 1 }\n"
    expect(verdict(original, original.sub("+ 1", "+ 2"))).not_to be_proven_equivalent
  end

  it "does not prove a changed rescue clause equivalent" do
    original = "def a\n  1\nrescue ArgumentError\n  2\nend\n"
    expect(verdict(original, original.sub("ArgumentError", "TypeError"))).not_to be_proven_equivalent
  end

  it "does not prove a renamed local variable equivalent" do
    expect(verdict("def a\n  x = 1\n  x\nend\n", "def a\n  y = 1\n  y\nend\n")).not_to be_proven_equivalent
  end

  it "fails toward running when the mutated source does not compile" do
    verdict = verdict("def a = 1\n", "def a = (\n")
    expect(verdict.reason).to eq(:compile_failed)
    expect(verdict).not_to be_proven_equivalent
  end

  describe "line numbers" do
    let(:original) { "def a\n  raise 'x'\nend\n" }
    let(:shifted) { "def a\n\n  raise 'x'\nend\n" }

    it "treats a moved line as different in strict mode" do
      expect(verdict(original, shifted, level: :strict)).not_to be_proven_equivalent
    end

    it "ignores a moved line in relaxed mode when nothing reflects on lines" do
      expect(verdict(original, shifted, level: :relaxed)).to be_proven_equivalent
    end

    it "refuses relaxed proof when the source reflects on its own location" do
      reflective = "def a\n  caller\nend\n"
      expect(verdict(reflective, "def a\n\n  caller\nend\n", level: :relaxed).reason).to eq(:reflection)
    end
  end

  describe "known equivalent shapes (positive controls)" do
    it "proves a changed branch the compiler removes behind a constant condition" do
      original = "def a\n  if true then 1 else 2 end\nend\n"
      expect(verdict(original, original.sub("2", "3"))).to be_proven_equivalent
    end

    it "proves a changed statement behind a modifier on false" do
      expect(verdict("def a\n  1 if false\nend\n", "def a\n  2 if false\nend\n")).to be_proven_equivalent
    end

    it "does not prove a changed statement after return, which the compiler keeps" do
      expect(verdict("def a\n  return 1\n  2\nend\n", "def a\n  return 1\n  3\nend\n")).not_to be_proven_equivalent
    end
  end

  it "records the compiler pin" do
    expect(TrivialEquivalence::CompilerPin.description).to include(RUBY_VERSION)
  end
end
