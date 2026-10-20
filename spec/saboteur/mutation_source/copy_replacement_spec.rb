# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/copy_replacement"

RSpec.describe Saboteur::MutationSource::CopyReplacement do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body, prefix: "")
    subjects_in("#{prefix}class CopyExample\n  def apply(items)\n    #{body}\n  end\nend\n").first
  end

  def results(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits) }
  end

  def body_of(text)
    "def apply(items)\n    #{text}\n  end"
  end

  %w[dup clone].each do |call|
    it "drops #{call} and a test of the original's isolation kills it" do
      subject = subject_for("items.#{call} << :added")
      mutation = source.mutations_for(subject).fetch(0)
      expect(mutation.operator).to eq("copy_replacement")
      expect(mutation.coarse).to be(false)
      expect(mutation.source).to eq("copy_replacement")
      expect(subject.apply(mutation.edits)).to include("items << :added")
      original = [1]
      Class.new { class_eval(subject.source) }.new.apply(original)
      expect(original).to eq([1])
      Class.new { class_eval(subject.apply(mutation.edits)) }.new.apply(original)
      expect(original).to eq([1, :added])
    end
  end

  it "makes deep_dup shallow, so the inner object is shared" do
    expect(results("items.deep_dup")).to eq([body_of("items.dup")])
  end

  it "drops a dup with empty parentheses, and keeps safe navigation's receiver" do
    expect(results("items.dup()")).to eq([body_of("items")])
    expect(results("items&.dup")).to eq([body_of("items")])
  end

  it "drops only the call on a longer chain and keeps what follows it" do
    expect(results("items.map(&:to_s).dup.sort")).to eq([body_of("items.map(&:to_s).sort")])
  end

  it "mutates each copy in a statement on its own" do
    expect(results("[items.dup, items.clone]")).to eq([body_of("[items, items.clone]"), body_of("[items.dup, items]")])
  end

  it "leaves alone a copy with arguments, a block, or no receiver, and other calls" do
    ["items.clone(freeze: false)", "items.dup { 1 }", "dup", "items.deep_dup(1)", "items.freeze",
     "items.deep_clone"].each do |body|
      expect(results(body)).to eq([])
    end
  end

  it "skips arid statements" do
    expect(results("puts items.dup")).to eq([])
  end

  it "does not visit nested singleton class or method scopes" do
    ["class << items; def apply; items.dup; end; end", "def inner(items); items.dup; end"].each do |body|
      expect(results(body)).to be_empty, body
    end
  end

  it "stops at class and module scope nodes" do
    ["class Nested; items.dup; end", "module Nested; items.dup; end", "class << items; items.dup; end"].each do |body|
      subject = double("subject", body_node: Prism.parse(body).value.statements)
      expect(source.mutations_for(subject)).to be_empty
    end
  end

  it "walks into the receiver and arguments of a call it leaves alone" do
    expect(results("items.map(&:to_s).first(items.dup.size)")).to eq([body_of("items.map(&:to_s).first(items.size)")])
  end

  it "keeps the digest stable after a multibyte comment above the method" do
    digests = [subject_for("items.dup"), subject_for("items.dup", prefix: "# héllo\n")].map do |subject|
      source.mutations_for(subject).fetch(0).digest(subject_start: subject.start_byte,
                                                    original_source: subject.file_source)
    end
    expect(digests.uniq.size).to eq(1)
  end
end
