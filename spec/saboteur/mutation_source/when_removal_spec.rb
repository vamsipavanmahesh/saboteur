# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/when_removal"

RSpec.describe Saboteur::MutationSource::WhenRemoval do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body)
    subjects_in("class WhenExample\n  def pick(x)\n#{body}\n  end\nend\n").first
  end

  def replacements(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits).lines[1..-2].join }
  end

  let(:three) { "    case x\n    when 1 then :a\n    when 2\n      :b\n    else\n      :c\n    end" }

  it "removes each when branch on its own" do
    expect(replacements(three)).to eq(["    case x\n    when 2\n      :b\n    else\n      :c\n    end\n",
                                       "    case x\n    when 1 then :a\n    else\n      :c\n    end\n"])
  end

  it "removes the last branch of a case without an else" do
    expect(replacements("    case x\n    when 1 then :a\n    when 2 then :b\n    end"))
      .to eq(["    case x\n    when 2 then :b\n    end\n", "    case x\n    when 1 then :a\n    end\n"])
  end

  it "handles a one-line case" do
    expect(replacements("    case x when 1 then :a when 2 then :b else :c end"))
      .to eq(["    case x when 2 then :b else :c end\n", "    case x when 1 then :a else :c end\n"])
  end

  it "mutates a case with no subject" do
    expect(replacements("    case\n    when x then 1\n    when !x then 2\n    end").size).to eq(2)
  end

  it "gives every mutant a parseable method" do
    [three, "    case x\n    when 1, 2 then :a\n    when 3 then :b\n    end"].each do |body|
      subject = subject_for(body)
      source.mutations_for(subject).each do |mutation|
        expect(Prism.parse(subject.apply(mutation.edits)).errors).to be_empty
      end
    end
  end

  it "leaves a case with a single when alone, since a case needs one" do
    expect(replacements("    case x\n    when 1 then :a\n    else :b\n    end")).to be_empty
    expect(replacements("    case x\n    when 1 then :a\n    end")).to be_empty
  end

  it "leaves other conditionals and pattern matching alone" do
    expect(replacements("    if x then 1 else 2 end")).to be_empty
    expect(replacements("    case x\n    in 1 then :a\n    in 2 then :b\n    end")).to be_empty
  end

  it "leaves a branch that opens a heredoc alone, since its body lives on later lines" do
    body = "    case x\n    when 1 then <<~TEXT\n      hi\n    TEXT\n    when 2 then :b\n    end"
    expect(replacements(body)).to eq(["    case x\n    when 1 then <<~TEXT\n      hi\n    TEXT\n    end\n"])
  end

  it "mutates nested cases in the branches too" do
    inner = "      case x\n      when 1 then 1\n      when 2 then 2\n      end"
    body = "    case x\n    when 1\n#{inner}\n    when 2 then 3\n    end"
    expect(replacements(body).size).to eq(4)
  end

  it "skips arid statements and nested definitions" do
    expect(replacements("    def inner\n#{three}\n    end")).to be_empty
    expect(described_class.new(arid: ["case x"]).mutations_for(subject_for(three))).to be_empty
    expect(replacements(three)).not_to be_empty
  end

  it "keeps the mutation metadata" do
    mutation = source.mutations_for(subject_for(three)).fetch(0)
    expect(mutation.operator).to eq("when_removal")
    expect(mutation.coarse).to be(false)
    expect(mutation.source).to eq("when_removal")
  end

  it "produces a mutant a test that takes the branch kills" do
    subject = subject_for(three)
    mutation = source.mutations_for(subject).fetch(0)
    correct = Class.new { class_eval(subject.source) }.new
    changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
    expect(correct.pick(1)).to eq(:a)
    expect(changed.pick(1)).to eq(:c)
  end

  it "is wired into the built-in source, selectable alone, and honors custom arid" do
    subject = subject_for(three)
    expect(Saboteur::MutationSource::Builtin.new(operators: ["when_removal"]).mutations_for(subject).map(&:operator))
      .to eq(%w[when_removal when_removal])
    without = Saboteur::MutationSource::Builtin.new(exclude_operators: ["when_removal"])
    expect(without.mutations_for(subject).map(&:operator)).not_to include("when_removal")
    arid = Saboteur::MutationSource::Builtin.new(arid: ["case x"], operators: ["when_removal"])
    expect(arid.mutations_for(subject)).to be_empty
  end
end
