# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::BytecodeEquivalence do
  subject(:filter) { described_class.new }

  let(:original) { "def clamp(x)\n  x < 0 ? 0 : x\nend" }

  it "treats a different line layout and comments as equivalent" do
    reformatted = "def clamp(x)\n  x < 0 ? 0 : x # same\n\n\nend"

    expect(filter.equivalent?(original, reformatted)).to be(true)
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

    expect(RubyVM::InstructionSequence).to have_received(:compile).with(original).once
  end

  it "compiles a different original when the method changes" do
    other = "def other(x)\n  x\nend"

    expect(filter.equivalent?(original, original)).to be(true)
    expect(filter.equivalent?(other, other)).to be(true)
    expect(filter.equivalent?(other, original)).to be(false)
  end
end
