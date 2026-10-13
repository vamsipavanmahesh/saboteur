# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/endpoint_replacement"

RSpec.describe Saboteur::MutationSource::EndpointReplacement do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body, prefix: "")
    subjects_in("#{prefix}class EndpointExample\n  def choose(items)\n    #{body}\n  end\nend\n").first
  end

  %w[first last].each do |name|
    it "swaps #{name} and an order-sensitive assertion kills the generated mutation" do
      subject = subject_for("items.#{name}")
      mutation = source.mutations_for(subject).fetch(0)
      expected = name == "first" ? :old : :new
      correct = Class.new { class_eval(subject.source) }.new
      changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
      expect(correct.choose(%i[old new])).to eq(expected)
      expect { expect(changed.choose(%i[old new])).to eq(expected) }
        .to raise_error(RSpec::Expectations::ExpectationNotMetError)
      expect(mutation.operator).to eq("endpoint_replacement")
      expect(mutation.source).to eq("endpoint_replacement")
      expect(mutation.coarse).to be(false)
    end
  end

  it "does not guess at bare calls, argument-bearing collection slices or block APIs" do
    ["first", "last", "items.each { true }", "items.size", "items.first(2)", "items.last(1)", "items.first { true }",
     "items.fetch(0)",
     "items.public_send(:first)"].each do |body|
      expect(source.mutations_for(subject_for(body))).to be_empty, body
    end
  end

  it "preserves safe navigation, comments, spacing and a multibyte prefix digest" do
    original = subject_for("items&.first # hi")
    shifted = subject_for("items&.first # hi", prefix: "# héllo\n")
    mutants = [original, shifted].map { |subject| source.mutations_for(subject).fetch(0) }
    expect(original.apply(mutants.first.edits)).to include("items&.last # hi")
    digests = [original, shifted].zip(mutants).map do |subject, mutation|
      mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    end
    expect(digests.uniq.size).to eq(1)
  end

  it "skips arid calls and nested method/class/module/singleton-class scopes" do
    ["logger.info(items.first)", "def inner; items.first; end",
     "class << items; def x; self.last; end; end"].each do |body|
      expect(source.mutations_for(subject_for(body))).to be_empty
    end
  end

  it "accepts an empty method body without visiting a node" do
    subject = double("subject", node: double("definition", body: nil))
    expect(source.mutations_for(subject)).to be_empty
  end

  it "stops at class and module scope nodes" do
    ["class Nested; def x; items.last; end; end", "module Nested; def x; items.first; end; end"].each do |body|
      subject = double("subject", node: double("definition", body: Prism.parse(body).value.statements))
      expect(source.mutations_for(subject)).to be_empty
    end
  end

  it "walks nested calls in deterministic order and is appended by builtin" do
    subject = subject_for("items.first.last")
    found = source.mutations_for(subject)
    expect(found.size).to eq(2)
    expect(found.map { |mutation| Prism.parse(subject.apply(mutation.edits)).success? }).to eq([true, true])
    builtin = Saboteur::MutationSource::Builtin.new.mutations_for(subject)
    expect(builtin.last(2).map(&:operator)).to eq(%w[endpoint_replacement endpoint_replacement])
  end
end
