# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/unary_insertion"

RSpec.describe Saboteur::MutationSource::UnaryInsertion do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body)
    subjects_in("class InsertExample\n  def calc(x, y)\n    #{body}\n  end\nend\n").first
  end

  def replacements(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits).lines[1..-2].join.strip }
  end

  it "negates each operand of a boolean connector, one at a time" do
    expect(replacements("a && b")).to eq(["!a && b", "a && !b"])
    expect(replacements("a || b")).to eq(["!a || b", "a || !b"])
  end

  it "negates call and instance variable operands" do
    expect(replacements("ok? || other?(x)")).to eq(["!ok? || other?(x)", "ok? || !other?(x)"])
    expect(replacements("@ready && ok")).to eq(["!@ready && ok", "@ready && !ok"])
  end

  it "negates each operand of a longer chain" do
    expect(replacements("a && b && c")).to eq(["!a && b && c", "a && !b && c", "a && b && !c"])
  end

  it "inserts a unary minus before each arithmetic operand" do
    expect(replacements("x + y")).to eq(["-x + y", "x + -y"])
    expect(replacements("total * count")).to eq(["-total * count", "total * -count"])
    expect(replacements("x - y")).to eq(["-x - y", "x - -y"])
  end

  it "leaves string concatenation alone, since unary minus keeps a String's characters" do
    expect(replacements('name + "!"')).to be_empty
    expect(replacements('"<" + name')).to be_empty
    expect(replacements("\"pre \#{name} mid\" + tail")).to be_empty
    expect(replacements('name + "!" + more')).to be_empty
  end

  it "treats a nested concatenation as a string operand on either side" do
    expect(replacements('"a" + x + y')).to be_empty
    expect(replacements('x + "s" + y')).to be_empty
  end

  it "still mutates the operands of a sum that only yields a String at runtime" do
    expect(replacements("a + b - c")).to eq(["-a + b - c", "a + -b - c", "a + b - -c"])
    expect(replacements('a + "s".+(b)')).to eq(['-a + "s".+(b)', 'a + -"s".+(b)'])
  end

  it "leaves literal operands to the literal operators" do
    expect(replacements("1 + x")).to eq(["1 + -x"])
    expect(replacements("x + 2")).to eq(["-x + 2"])
    expect(replacements("1 + 2")).to be_empty
    expect(replacements("true && ok")).to eq(["true && !ok"])
  end

  it "leaves operands that already carry a unary operator alone" do
    expect(replacements("!a && b")).to eq(["!a && !b"])
    expect(replacements("-x + y")).to eq(["-x + -y"])
  end

  it "leaves a bare predicate to condition_negation" do
    expect(replacements("if ok\n      1\n    end")).to be_empty
    expect(replacements("ok ? 1 : 2")).to be_empty
  end

  it "negates inside a parenthesized group but leaves the group itself to condition_negation" do
    expect(replacements("(a || b) && c")).to eq(["(!a || b) && c", "(a || !b) && c", "(a || b) && !c"])
  end

  it "skips arid statements" do
    expect(replacements("puts a && b")).to be_empty
    expect(replacements("Rails.logger.info x + y")).to be_empty
  end

  it "names its operator and source" do
    expect(subject_for("a && b").then do |subject|
      source.mutations_for(subject).map do |m|
        [m.operator, m.source]
      end.uniq
    end)
      .to eq([%w[unary_insertion unary_insertion]])
  end

  it "leaves the explicit call spelling alone" do
    expect(replacements("x.+(y)")).to be_empty
  end

  it "skips a block-carrying argument but still mutates a plain receiver" do
    expect(replacements("x + y { 1 }")).to eq(["-x + y { 1 }"])
  end

  it "leaves a call that carries a block alone" do
    expect(replacements("items.map { |i| i } && done")).to eq(["items.map { |i| i } && !done"])
  end

  it "treats only the prefix spelling of a unary operator as already negated" do
    expect(replacements("a && x.-@")).to eq(["!a && x.-@", "a && !x.-@"])
    expect(replacements("~x + y")).to eq(["~x + -y"])
  end
end
