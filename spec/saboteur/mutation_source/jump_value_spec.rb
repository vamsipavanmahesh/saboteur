# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/jump_value"

RSpec.describe Saboteur::MutationSource::JumpValue do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body, name: "pick", params: "(a, b)")
    subjects_in("class JumpExample\n  def #{name}#{params}\n    #{body}\n  end\nend\n").first
  end

  def replacements(body, **)
    subject = subject_for(body, **)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits).lines[1..-2].join.strip }
  end

  it "replaces the value of return, next and break with nil" do
    expect(replacements("return a if b")).to eq(["return nil if b"])
    expect(replacements("[a].each { |x| next x }")).to eq(["[a].each { |x| next nil }"])
    expect(replacements("[a].each { |x| break x }")).to eq(["[a].each { |x| break nil }"])
  end

  it "replaces a list of values, a parenthesized value and an array as one value" do
    expect(replacements("return a, b")).to eq(["return nil"])
    expect(replacements("return(a)")).to eq(["return nil"])
    expect(replacements("return [a, b]")).to eq(["return nil"])
    expect(replacements("return[a]")).to eq(["return nil"])
  end

  it "mutates every jump in the method, one at a time" do
    expect(replacements("return a if b\n    return b"))
      .to eq(["return nil if b\n    return b", "return a if b\n    return nil"])
  end

  it "leaves a bare jump and a jump that already returns nil alone" do
    expect(replacements("return if a")).to be_empty
    expect(replacements("return nil")).to be_empty
    expect(replacements("[a].each { |x| next }")).to be_empty
  end

  it "mutates a value that merely contains nil" do
    expect(replacements("return a.nil?")).to eq(["return nil"])
    expect(replacements("return [nil]")).to eq(["return nil"])
  end

  it "leaves a heredoc value alone, since its body lives on later lines" do
    expect(replacements("return <<~TEXT\n      hi\n    TEXT")).to be_empty
    expect(replacements("return [<<~TEXT]\n      hi\n    TEXT")).to be_empty
  end

  it "skips setters and initialize, whose result the caller discards" do
    expect(replacements("return a", name: "value=", params: "(a)")).to be_empty
    expect(replacements("return a", name: "initialize", params: "(a)")).to be_empty
    expect(replacements("return a", name: "[]=", params: "(a, b)")).to be_empty
    expect(replacements("return a", name: "[]", params: "(a)")).not_to be_empty
    expect(replacements("return a", name: "value_of", params: "(a)")).not_to be_empty
    expect(replacements("return a", name: "==", params: "(a)")).not_to be_empty
  end

  it "skips arid statements and nested definitions" do
    expect(replacements("def inner; return a; end")).to be_empty
    expect(described_class.new(arid: ["a"]).mutations_for(subject_for("return a"))).to be_empty
    expect(replacements("return a")).not_to be_empty
  end

  it "keeps the mutation metadata" do
    mutation = source.mutations_for(subject_for("return a")).fetch(0)
    expect(mutation.operator).to eq("jump_value")
    expect(mutation.coarse).to be(false)
    expect(mutation.source).to eq("jump_value")
  end

  it "produces a mutant an assertion on the returned value kills" do
    subject = subject_for("return a if b\n    :other")
    mutation = source.mutations_for(subject).fetch(0)
    correct = Class.new { class_eval(subject.source) }.new
    changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
    expect(correct.pick(1, true)).to eq(1)
    expect(changed.pick(1, true)).to be_nil
  end

  it "gives the same mutants through the built-in source, and is selectable alone" do
    subject = subject_for("return a if b")
    builtin = Saboteur::MutationSource::Builtin.new(operators: ["jump_value"])
    expect(builtin.mutations_for(subject).map(&:operator)).to eq(["jump_value"])
    without = Saboteur::MutationSource::Builtin.new(exclude_operators: ["jump_value"])
    expect(without.mutations_for(subject).map(&:operator)).not_to include("jump_value")
  end
end
