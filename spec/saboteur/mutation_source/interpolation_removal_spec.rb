# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/interpolation_removal"

RSpec.describe Saboteur::MutationSource::InterpolationRemoval do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body)
    subjects_in("class InterpExample\n  def greet(name)\n    #{body}\n  end\nend\n").first
  end

  def replacements(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits) }
  end

  it "removes the interpolation and each literal segment in turn" do
    expect(replacements("\"Hello, \#{name}!\""))
      .to eq(["def greet(name)\n    \"\#{name}!\"\n  end",
              "def greet(name)\n    \"Hello, !\"\n  end",
              "def greet(name)\n    \"Hello, \#{name}\"\n  end"])
  end

  it "removes each interpolation and the literal segment between them separately" do
    expect(replacements("\"\#{a} and \#{b}\""))
      .to eq(["def greet(name)\n    \" and \#{b}\"\n  end",
              "def greet(name)\n    \"\#{a}\#{b}\"\n  end",
              "def greet(name)\n    \"\#{a} and \"\n  end"])
  end

  it "keeps the mutation metadata" do
    subject = subject_for("\"Hello, \#{name}!\"")
    mutation = source.mutations_for(subject).fetch(0)
    expect(mutation.operator).to eq("interpolation_removal")
    expect(mutation.coarse).to be(false)
    expect(mutation.source).to eq("interpolation_removal")
  end

  it "leaves plain strings to literal_replacement" do
    expect(replacements('"hello"')).to be_empty
  end

  it "leaves backticks to the hazard guard" do
    expect(replacements("`echo \#{name}`")).to be_empty
  end

  it "produces a mutant an output assertion kills" do
    subject = subject_for("\"Hello, \#{name}!\"")
    mutation = source.mutations_for(subject).fetch(1) # drop the interpolation
    correct = Class.new { class_eval(subject.source) }.new
    changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
    expect(correct.greet("Ada")).to eq("Hello, Ada!")
    expect { expect(changed.greet("Ada")).to eq("Hello, Ada!") }
      .to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end
end
