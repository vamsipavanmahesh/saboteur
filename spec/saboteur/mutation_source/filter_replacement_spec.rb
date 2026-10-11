# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/filter_replacement"

RSpec.describe Saboteur::MutationSource::FilterReplacement do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body, prefix: "")
    subjects_in("#{prefix}class FilterExample\n  def apply(items, &predicate)\n    #{body}\n  end\nend\n").first
  end

  def replacements(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits) }
  end

  { "select" => "reject", "reject" => "select", "select!" => "reject!",
    "reject!" => "select!" }.each do |original, replacement|
    it "swaps #{original} with #{replacement} and an output assertion kills it" do
      subject = subject_for("items.#{original} { |item| item == :remove }")
      mutation = source.mutations_for(subject).fetch(0)
      expect(mutation.operator).to eq("filter_replacement")
      expect(mutation.coarse).to be(false)
      expect(mutation.source).to eq("filter_replacement")
      expect(subject.apply(mutation.edits)).to include("items.#{replacement} { |item| item == :remove }")
      correct = Class.new { class_eval(subject.source) }.new
      changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
      expected = original.start_with?("select") ? [:remove] : [:keep]
      expect(correct.apply(%i[keep remove])).to eq(expected)
      expect { expect(changed.apply(%i[keep remove])).to eq(expected) }
        .to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end

    it "keeps the #{original} digest stable after a multibyte comment above the method" do
      body = "items.#{original} { |item| item == :remove }"
      before = subject_for(body)
      after = subject_for(body, prefix: "# héllo\n")
      digests = [before, after].map do |subject|
        source.mutations_for(subject).fetch(0).digest(subject_start: subject.start_byte,
                                                      original_source: subject.file_source)
      end
      expect(digests.uniq.size).to eq(1)
    end
  end

  it "changes only the message bytes and keeps safe navigation, comments and block formatting" do
    body = "items&.select do |item| # héllo\n      item\n    end"
    expect(replacements(body)).to eq(["def apply(items, &predicate)\n    #{body.sub('select', 'reject')}\n  end"])
  end

  it "accepts a forwarded block and an explicit receiver" do
    expect(replacements("items.reject(&predicate)").first).to include("items.select(&predicate)")
    expect(replacements("self.select { true }").first).to include("self.reject { true }")
  end

  it "does not guess at SQL select arguments, bare calls or an unconsumed enumerator" do
    ["items.select(:name)", "items.select(:name) { true }", "items.select", "select { true }",
     "items.map { true }", "items.public_send(:select) { true }"].each do |body|
      expect(replacements(body)).to be_empty, body
    end
  end

  it "leaves configured arid statements and their children untouched" do
    expect(replacements("logger.info(items.select { true })")).to be_empty
    custom = described_class.new(arid: [/\Atrack\b/])
    expect(custom.mutations_for(subject_for("track(items.reject { true })"))).to be_empty
  end

  it "does not visit nested singleton class or method scopes" do
    ["class << items; def apply; self.select { true }; end; end",
     "def inner(items); items.select { true }; end"].each do |body|
      expect(replacements(body)).to be_empty, body
    end
  end

  it "stops at class and module scope nodes" do
    ["class Nested; def apply(items); items.select { true }; end; end",
     "module Nested; def apply(items); items.select { true }; end; end"].each do |body|
      statements = Prism.parse(body).value.statements
      subject = double("subject", node: double("definition", body: statements))
      expect(source.mutations_for(subject)).to be_empty
    end
  end

  it "walks nested blocks in source order and emits parseable, distinct edits" do
    subject = subject_for("items.select { |item| item.reject { true }.empty? }")
    found = source.mutations_for(subject)
    expect(found.size).to eq(2)
    expect(found.map { |mutation| subject.apply(mutation.edits) }.uniq.size).to eq(2)
    expect(found.map { |mutation| Prism.parse(subject.apply(mutation.edits)).success? }).to eq([true, true])
    expect(found.map { |mutation| mutation.edits.first.start_byte }).to eq(found.map { |m|
      m.edits.first.start_byte
    }.sort)
  end

  it "is included by builtin without changing the earlier operators' order" do
    subject = subject_for("items.select { |item| item == :remove }")
    found = Saboteur::MutationSource::Builtin.new.mutations_for(subject)
    expect(found.first(2).map(&:operator)).to eq(%w[body_nil body_raise])
    expect(found.last.operator).to eq("filter_replacement")
  end
end
