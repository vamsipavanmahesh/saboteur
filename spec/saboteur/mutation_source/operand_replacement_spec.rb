# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/operand_replacement"

RSpec.describe Saboteur::MutationSource::OperandReplacement do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body)
    subjects_in("class OperandExample\n  def calc(a, b)\n    #{body}\n  end\nend\n").first
  end

  def replacements(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits) }
  end

  it "replaces a + b with each operand" do
    expect(replacements("a + b")).to eq(["def calc(a, b)\n    a\n  end", "def calc(a, b)\n    b\n  end"])
  end

  it "covers the arithmetic and comparison families" do
    %w[+ - * / % ** < <= > >= == !=].each do |operator|
      expect(replacements("a #{operator} b").size).to eq(2), "expected two mutants for a #{operator} b"
    end
  end

  it "keeps the mutation metadata" do
    subject = subject_for("a + b")
    mutation = source.mutations_for(subject).fetch(0)
    expect(mutation.operator).to eq("operand_replacement")
    expect(mutation.coarse).to be(false)
    expect(mutation.source).to eq("operand_replacement")
  end

  it "leaves boolean connectors to boolean_logic" do
    expect(replacements("a && b")).to be_empty
    expect(replacements("a || b")).to be_empty
  end

  it "leaves calls outside the binary shape alone" do
    expect(replacements("a.foo(b)")).to be_empty
    expect(replacements("a.+(b, c)")).to be_empty
    expect(replacements("a.+(b) { |x| x }")).to be_empty
  end

  it "produces a mutant an output assertion kills" do
    subject = subject_for("a + b")
    mutation = source.mutations_for(subject).fetch(1) # a + b -> b
    correct = Class.new { class_eval(subject.source) }.new
    changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
    expect(correct.calc(2, 3)).to eq(5)
    expect { expect(changed.calc(2, 3)).to eq(5) }
      .to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end
end
