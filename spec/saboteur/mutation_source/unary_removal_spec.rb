# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/unary_removal"

RSpec.describe Saboteur::MutationSource::UnaryRemoval do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body)
    subjects_in("class UnaryExample\n  def calc(x, y)\n    #{body}\n  end\nend\n").first
  end

  def replacements(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits).lines[1..-2].join.strip }
  end

  it "drops a unary minus and a bitwise complement" do
    expect(replacements("-x")).to eq(["x"])
    expect(replacements("~x")).to eq(["x"])
  end

  it "keeps the rest of the expression and the operand's own shape" do
    expect(replacements("y * -x")).to eq(["y * x"])
    expect(replacements("-(x + y)")).to eq(["(x + y)"])
    expect(replacements("-x.abs")).to eq(["x.abs"])
    expect(replacements("- x")).to eq(["x"])
  end

  it "mutates each unary operator in an expression" do
    expect(replacements("-x + ~y")).to eq(["x + ~y", "-x + y"])
  end

  it "mutates nested operators one at a time" do
    expect(replacements("-(-x)")).to eq(["(-x)", "-(x)"])
  end

  it "leaves unary plus, logical not and literals alone" do
    expect(replacements("+x")).to be_empty
    expect(replacements("!x")).to be_empty
    expect(replacements("-1")).to be_empty
    expect(replacements("-1.5")).to be_empty
  end

  it "leaves the explicit call spelling and binary operators alone" do
    expect(replacements("x.-@")).to be_empty
    expect(replacements("x - y")).to be_empty
    expect(replacements("x.~")).to be_empty
  end

  it "gives every mutant a parseable method" do
    ["-x ** 2", "y * -x", "-(x + y)", "~x & y", "[-x, ~y]", "-x.abs", "foo(-x)"].each do |body|
      subject = subject_for(body)
      source.mutations_for(subject).each do |mutation|
        expect(Prism.parse(subject.apply(mutation.edits)).errors).to be_empty
      end
    end
  end

  it "skips arid statements and nested definitions" do
    expect(replacements("def inner\n      -x\n    end")).to be_empty
    expect(described_class.new(arid: ["-x"]).mutations_for(subject_for("-x"))).to be_empty
    expect(replacements("-x")).not_to be_empty
  end

  it "keeps the mutation metadata" do
    mutation = source.mutations_for(subject_for("-x")).fetch(0)
    expect(mutation.operator).to eq("unary_removal")
    expect(mutation.coarse).to be(false)
    expect(mutation.source).to eq("unary_removal")
  end

  it "produces a mutant an assertion on a non-zero value kills" do
    subject = subject_for("-x")
    mutation = source.mutations_for(subject).fetch(0)
    correct = Class.new { class_eval(subject.source) }.new
    changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
    expect(correct.calc(3, 0)).to eq(-3)
    expect(changed.calc(3, 0)).to eq(3)
  end

  it "is wired into the built-in source, selectable alone, and honors custom arid" do
    subject = subject_for("-x")
    expect(Saboteur::MutationSource::Builtin.new(operators: ["unary_removal"]).mutations_for(subject).map(&:operator))
      .to eq(["unary_removal"])
    without = Saboteur::MutationSource::Builtin.new(exclude_operators: ["unary_removal"])
    expect(without.mutations_for(subject).map(&:operator)).not_to include("unary_removal")
    arid = Saboteur::MutationSource::Builtin.new(arid: ["-x"], operators: ["unary_removal"])
    expect(arid.mutations_for(subject)).to be_empty
  end
end
