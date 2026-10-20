# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/rescue_removal"

RSpec.describe Saboteur::MutationSource::RescueRemoval do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body)
    subjects_in("class RescueExample\n  def risky(a)\n#{body}\n  end\nend\n").first
  end

  def replacements(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits).lines[1..-2].join }
  end

  it "removes the only rescue clause of a method body" do
    expect(replacements("    a.call\n    rescue ArgumentError\n    0")).to eq(["    a.call\n    \n"])
  end

  it "removes each clause of a chain on its own" do
    expect(replacements("    a.call\n  rescue TypeError\n    1\n  rescue ArgumentError\n    2"))
      .to eq(["    a.call\n  rescue ArgumentError\n    2\n", "    a.call\n  rescue TypeError\n    1\n  \n"])
  end

  it "removes the clause of a begin block and keeps ensure" do
    expect(replacements("    begin\n      a.call\n    rescue\n      0\n    ensure\n      a.done\n    end"))
      .to eq(["    begin\n      a.call\n    \n    ensure\n      a.done\n    end\n"])
  end

  it "keeps the only handler of a block with an else, since else alone does not parse" do
    expect(replacements("    begin\n      a.call\n    rescue\n      0\n    else\n      1\n    end")).to be_empty
    chain = "    begin\n      a.call\n    rescue TypeError\n      0\n    rescue\n      2\n    else\n      1\n    end"
    expect(replacements(chain).size).to eq(2)
  end

  it "removes the tail of a rescue modifier" do
    expect(replacements("    value = a.call rescue nil\n    value")).to eq(["    value = a.call\n    value\n"])
    expect(replacements("    a.call rescue nil")).to eq(["    a.call\n"])
  end

  it "gives every mutant a parseable method" do
    bodies = ["    a.call\n    rescue\n    0", "    a.call\n  rescue A\n    1\n  rescue B\n    2\n  else\n    3",
              "    a.call rescue nil", "    begin\n      a\n    rescue\n      b\n    end"]
    bodies.each do |body|
      subject = subject_for(body)
      source.mutations_for(subject).each do |mutation|
        expect(Prism.parse(subject.apply(mutation.edits)).errors).to be_empty
      end
    end
  end

  it "leaves code without a handler alone" do
    expect(replacements("    a.call\n    ensure\n    a.done")).to be_empty
    expect(replacements("    a.call")).to be_empty
  end

  it "leaves a handler that opens a heredoc alone, since its body lives on later lines" do
    expect(replacements("    a.call\n    rescue\n    <<~TEXT\n      hi\n    TEXT")).to be_empty
    expect(replacements("    a.call rescue <<~TEXT\n      hi\n    TEXT")).to be_empty
  end

  it "skips arid statements and nested definitions" do
    expect(replacements("    def inner\n      a\n    rescue\n      b\n    end")).to be_empty
    arid = described_class.new(arid: ["a.call"])
    expect(arid.mutations_for(subject_for("    a.call rescue nil"))).to be_empty
    expect(replacements("    a.call rescue nil")).not_to be_empty
  end

  it "keeps the mutation metadata" do
    mutation = source.mutations_for(subject_for("    a.call rescue nil")).fetch(0)
    expect(mutation.operator).to eq("rescue_removal")
    expect(mutation.coarse).to be(false)
    expect(mutation.source).to eq("rescue_removal")
  end

  it "produces a mutant a test that raises the error kills" do
    subject = subject_for("    a.call rescue :fallback")
    mutation = source.mutations_for(subject).fetch(0)
    correct = Class.new { class_eval(subject.source) }.new
    changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
    failing = -> { raise "boom" }
    expect(correct.risky(failing)).to eq(:fallback)
    expect { changed.risky(failing) }.to raise_error("boom")
  end

  it "is wired into the built-in source and selectable alone" do
    subject = subject_for("    a.call rescue nil")
    builtin = Saboteur::MutationSource::Builtin.new(operators: ["rescue_removal"])
    expect(builtin.mutations_for(subject).map(&:operator)).to eq(["rescue_removal"])
    without = Saboteur::MutationSource::Builtin.new(exclude_operators: ["rescue_removal"])
    expect(without.mutations_for(subject).map(&:operator)).not_to include("rescue_removal")
  end

  it "wires custom arid patterns through the built-in source" do
    builtin = Saboteur::MutationSource::Builtin.new(arid: ['\Aa\.call\b'])
    expect(builtin.mutations_for(subject_for("    a.call rescue nil\n    a.other rescue nil")).map(&:operator))
      .to include("rescue_removal").and(satisfy { |ops| ops.count("rescue_removal") == 1 })
  end
end
