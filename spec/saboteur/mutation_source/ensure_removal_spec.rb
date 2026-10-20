# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/ensure_removal"

RSpec.describe Saboteur::MutationSource::EnsureRemoval do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body)
    subjects_in("class EnsureExample\n  def run(a)\n#{body}\n  end\nend\n").first
  end

  def replacements(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits).lines[1..-2].join }
  end

  it "removes the ensure clause of a method body" do
    expect(replacements("    a.call\n    ensure\n    a.done")).to eq(["    a.call\n"])
  end

  it "removes the ensure clause of a begin block and keeps the handler" do
    expect(replacements("    begin\n      a.call\n    rescue\n      0\n    ensure\n      a.done\n    end"))
      .to eq(["    begin\n      a.call\n    rescue\n      0\n    end\n"])
  end

  it "removes the ensure clause of a do block" do
    expect(replacements("    a.each do |x|\n      x.call\n    ensure\n      x.done\n    end"))
      .to eq(["    a.each do |x|\n      x.call\n    end\n"])
  end

  it "gives every mutant a parseable method" do
    bodies = ["    a.call\n    ensure\n    a.done",
              "    begin\n      a\n    rescue\n      b\n    else\n      c\n    ensure\n      d\n    end",
              "    begin\n      a\n    ensure\n      b\n    end"]
    bodies.each do |body|
      subject = subject_for(body)
      expect(source.mutations_for(subject).size).to eq(1)
      source.mutations_for(subject).each do |mutation|
        expect(Prism.parse(subject.apply(mutation.edits)).errors).to be_empty
      end
    end
  end

  it "leaves code without an ensure alone" do
    expect(replacements("    a.call\n    rescue\n    0")).to be_empty
    expect(replacements("    a.call")).to be_empty
  end

  it "leaves an ensure that opens a heredoc alone, since its body lives on later lines" do
    expect(replacements("    a.call\n    ensure\n    <<~TEXT\n      hi\n    TEXT")).to be_empty
  end

  it "skips arid statements and nested definitions" do
    expect(replacements("    def inner\n      a\n    ensure\n      b\n    end")).to be_empty
    arid = described_class.new(arid: ["a.call"])
    expect(arid.mutations_for(subject_for("    begin\n      a.call\n    ensure\n      b\n    end"))).to be_empty
    expect(replacements("    begin\n      b\n    ensure\n      b\n    end")).not_to be_empty
  end

  it "keeps the mutation metadata" do
    mutation = source.mutations_for(subject_for("    a.call\n    ensure\n    a.done")).fetch(0)
    expect(mutation.operator).to eq("ensure_removal")
    expect(mutation.coarse).to be(false)
    expect(mutation.source).to eq("ensure_removal")
  end

  it "produces a mutant a test that checks the cleanup kills" do
    subject = subject_for("    a.call\n    ensure\n    a.done")
    mutation = source.mutations_for(subject).fetch(0)
    correct = Class.new { class_eval(subject.source) }.new
    changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
    log = []
    probe = Struct.new(:log) do
      def call = log << :call
      def done = log << :done
    end
    correct.run(probe.new(log))
    expect(log).to eq(%i[call done])
    log.clear
    changed.run(probe.new(log))
    expect(log).to eq([:call])
  end

  it "is wired into the built-in source and selectable alone" do
    subject = subject_for("    a.call\n    ensure\n    a.done")
    builtin = Saboteur::MutationSource::Builtin.new(operators: ["ensure_removal"])
    expect(builtin.mutations_for(subject).map(&:operator)).to eq(["ensure_removal"])
    without = Saboteur::MutationSource::Builtin.new(exclude_operators: ["ensure_removal"])
    expect(without.mutations_for(subject).map(&:operator)).not_to include("ensure_removal")
  end
end
