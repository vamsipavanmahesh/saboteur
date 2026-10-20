# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::BytecodeEquivalence do
  subject(:filter) { described_class.new }

  let(:original) { "def clamp(x)\n  x < 0 ? 0 : x\nend" }

  # body_nil/statement_removal mutants put nil or a literal in void context,
  # which Ruby warns about when the host suite runs with -w: one line per
  # mutant floods stderr (#592, #656). The check is internal, so the
  # compiler's own warnings carry no signal - but a syntax error must still
  # count as not equivalent.
  it "suppresses Ruby's own compile warnings even when the process runs with -w" do
    verbose = $VERBOSE
    $VERBOSE = true
    expect do
      # A nil inserted in void context compiles away, so this pair IS
      # equivalent - and is exactly the shape -w warns about (#592's repro).
      expect(filter.equivalent?("def m\n  a = 1\n  a\nend", "def m\n  nil\n  a = 1\n  a\nend")).to be(true)
      # A mutant that does not parse still counts as not equivalent.
      expect(filter.equivalent?("def m\n  42\nend", "def m(\n")).to be(false)
    end.to output("").to_stderr
  ensure
    $VERBOSE = verbose
  end

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
      .with(anything, "saboteur/bytecode-equivalence", nil, 1, { frozen_string_literal: true }).twice
  end

  it "never equates an Integer with a Float" do
    expect(filter.equivalent?("def m\n  2\nend", "def m\n  2.0\nend")).to be(false)
    expect(filter.equivalent?("def m\n  [2]\nend", "def m\n  [2.0]\nend")).to be(false)
    expect(filter.equivalent?("def m\n  { 1 => :a }\nend", "def m\n  { 1.0 => :a }\nend")).to be(false)
    expect(filter.equivalent?("def m\n  2.0\nend", "def m\n  2.0\nend")).to be(true)
  end

  it "never equates +0.0 with -0.0, which divide to different infinities" do
    expect(filter.equivalent?("def m\n  1.0 / 0.0\nend", "def m\n  1.0 / -0.0\nend")).to be(false)
    expect(filter.equivalent?("def m\n  0.0\nend", "def m\n  -0.0\nend")).to be(false)
    expect(filter.equivalent?("def m\n  [0.0]\nend", "def m\n  [-0.0]\nend")).to be(false)
    expect(filter.equivalent?("def m\n  { 0.0 => 1 }\nend", "def m\n  { -0.0 => 1 }\nend")).to be(false)
    expect(filter.equivalent?("def m\n  -0.0\nend", "def m\n  -0.0\nend")).to be(true)
  end

  describe "structural comparison of operands" do
    def exact?(left, right)
      filter.send(:exact?, left, right)
    end

    it "separates containers of different size or kind" do
      expect(exact?([1], [1, 2])).to be(false)
      expect(exact?([1, 2], [1])).to be(false)
      expect(exact?([1], 1)).to be(false)
      expect(exact?(Array.new(8, 0), 0)).to be(false)
      expect(exact?([1, [2.0]], [1, [2.0]])).to be(true)
      expect(exact?([1, [2.0]], [1, [-2.0]])).to be(false)
    end

    it "separates a hash from a non-hash and compares hash pairs in order" do
      expect(exact?({ a: 1 }, [[:a, 1]])).to be(false)
      expect(exact?({ a: 1 }, { a: 1 })).to be(true)
      expect(exact?({ a: 1 }, { a: 2 })).to be(false)
      expect(exact?({ a: 0.0 }, { a: -0.0 })).to be(false)
    end

    it "compares the parts of a Complex or a Range, so a signed zero is a difference" do
      expect(exact?(Complex(0, 0.0), Complex(0, -0.0))).to be(false)
      expect(exact?(Complex(0.0, 1), Complex(-0.0, 1))).to be(false)
      expect(exact?(Complex(0, 1), Complex(0, 1.0))).to be(false)
      expect(exact?(Complex(0, 1.5), Complex(0, 1.5))).to be(true)
      expect(exact?(0.0..1, -0.0..1)).to be(false)
      expect(exact?(0..1.0, 0..-0.0)).to be(false)
      expect(exact?(1..2, 1...2)).to be(false)
      expect(exact?(1..2, 1..2)).to be(true)
    end

    it "treats operand types it cannot judge as different" do
      token = Object.new

      expect(exact?(token, token)).to be(false)
      expect(exact?(token, Object.new)).to be(false)
      expect(exact?(:a, :a)).to be(true)
      expect(exact?("a", "a")).to be(true)
      expect(exact?(nil, nil)).to be(true)
      expect(exact?(Rational(1, 2), Rational(1, 2))).to be(true)
    end

    it "separates a Float from an Integer and compares floats by their bytes" do
      expect(exact?(2.0, 2)).to be(false)
      expect(exact?(2.0, 2.0)).to be(true)
      expect(exact?(0.0, -0.0)).to be(false)
    end
  end

  it "never equates imaginary or range literals that differ in the sign of a zero" do
    expect(filter.equivalent?("def m\n  0.0i\nend", "def m\n  -0.0i\nend")).to be(false)
    expect(filter.equivalent?("def m\n  (0..0.0)\nend", "def m\n  (0..-0.0)\nend")).to be(false)
    expect(filter.equivalent?("def m\n  3i\nend", "def m\n  3i\nend")).to be(true)
  end

  it "keeps a mutant that holds NaN, which equals nothing" do
    expect(filter.equivalent?("def m\n  0.0 / 0.0\nend", "def m\n  1.0\nend")).to be(false)
  end

  it "puts $VERBOSE back after the check, as it was, also when the check raises" do
    verbose = $VERBOSE
    [true, false].each do |value|
      $VERBOSE = value
      filter.equivalent?(original, original)
      expect($VERBOSE).to be(value)
      expect { filter.send(:warnings_silenced) { raise "boom" } }.to raise_error("boom")
      expect($VERBOSE).to be(value)
    end
  ensure
    $VERBOSE = verbose
  end
end
