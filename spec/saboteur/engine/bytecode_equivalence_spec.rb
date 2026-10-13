# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::BytecodeEquivalence do
  subject(:filter) { described_class.new }

  let(:original) { "def clamp(x)\n  x < 0 ? 0 : x\nend" }

  it "treats a different line layout and comments as equivalent" do
    reformatted = "def clamp(x)\n  x < 0 ? 0 : x # same\n\n\nend"

    expect(filter.equivalent?(original, reformatted)).to be(true)
  end

  it "ignores line events when statements move between lines" do
    expect(filter.equivalent?("def m\n  a = 1\n  b = 2\n  a + b\nend",
                              "def m\n  a = 1; b = 2\n  a + b\nend")).to be(true)
  end

  it "tells apart methods that differ in name, locals, parameters or rescue clauses" do
    base = "def m(x)\n  x\nend"

    expect(filter.equivalent?(base, "def n(x)\n  x\nend")).to be(false)
    expect(filter.equivalent?(base, "def m(y)\n  y\nend")).to be(false)
    expect(filter.equivalent?(base, "def m(x = 1)\n  x\nend")).to be(false)
    expect(filter.equivalent?("def m\n  1\nrescue ArgumentError\n  2\nend",
                              "def m\n  1\nrescue TypeError\n  2\nend")).to be(false)
  end

  it "compares blocks nested in the method" do
    expect(filter.equivalent?("def m\n  [1].each { |x| x + 1 }\nend",
                              "def m\n  [1].each { |x| x - 1 }\nend")).to be(false)
    expect(filter.equivalent?("def m\n  [1].each { |x| x + 1 }\nend",
                              "def m\n  [1].each do |x|\n    x + 1\n  end\nend")).to be(true)
  end

  it "treats quote style as equivalent" do
    expect(filter.equivalent?("def m\n  \"a\"\nend", "def m\n  'a'\nend")).to be(true)
  end

  it "keeps a mutant that compiles differently" do
    expect(filter.equivalent?(original, "def clamp(x)\n  x < 1 ? 0 : x\nend")).to be(false)
  end

  it "keeps a mutant when the original cannot be compiled to compare" do
    expect(filter.equivalent?("def m(", "def m\nend")).to be(false)
    expect(filter.equivalent?("def m(", "def m(")).to be(false)
  end

  it "compiles the original once for all the mutants of one method" do
    allow(RubyVM::InstructionSequence).to receive(:compile).and_call_original

    filter.equivalent?(original, "def clamp(x)\n  x < 1 ? 0 : x\nend")
    filter.equivalent?(original, "def clamp(x)\n  x < 2 ? 0 : x\nend")

    expect(RubyVM::InstructionSequence).to have_received(:compile).with(original, any_args).once
  end

  it "compiles a different original when the method changes" do
    other = "def other(x)\n  x\nend"

    expect(filter.equivalent?(original, original)).to be(true)
    expect(filter.equivalent?(other, other)).to be(true)
    expect(filter.equivalent?(other, original)).to be(false)
  end

  it "does not collapse string literals that differ only in digits or hex" do
    expect(filter.equivalent?("def m\n  \"a(1)\"\nend", "def m\n  \"a(2)\"\nend")).to be(false)
    expect(filter.equivalent?("def m\n  \"0x123\"\nend", "def m\n  \"0x456\"\nend")).to be(false)
  end

  it "does not collapse numeric literals" do
    expect(filter.equivalent?("def m\n  10\nend", "def m\n  11\nend")).to be(false)
  end

  it "compiles under the file's frozen_string_literal setting" do
    allow(RubyVM::InstructionSequence).to receive(:compile).and_call_original

    filter.equivalent?("def m\n  \"a\"\nend", "def m\n  \"b\"\nend", frozen_string_literal: true)

    expect(RubyVM::InstructionSequence).to have_received(:compile)
      .with(anything, nil, nil, 1, { frozen_string_literal: true }).twice
  end

  it "never equates an Integer with a Float" do
    expect(filter.equivalent?("def m\n  2\nend", "def m\n  2.0\nend")).to be(false)
    expect(filter.equivalent?("def m\n  [2]\nend", "def m\n  [2.0]\nend")).to be(false)
    expect(filter.equivalent?("def m\n  { 1 => :a }\nend", "def m\n  { 1.0 => :a }\nend")).to be(false)
    expect(filter.equivalent?("def m\n  2.0\nend", "def m\n  2.0\nend")).to be(true)
  end
end
