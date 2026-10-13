# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::ConditionNegation do
  def target(expression)
    subjects_in("class ConditionTarget\n  def m(x)\n    #{expression}\n  end\nend\n").first
  end

  it "negates if unless modifier and ternary predicates with grouping" do
    ["if x; 1; else; 2; end", "unless x; 1; else; 2; end", "1 if x", "1 unless x", "x ? 1 : 2",
     "x.positive? ? 1 : 2"].each do |expression|
      subject = target(expression)
      list = described_class.new.mutations_for(subject)
      expect(list.size).to eq(1)
      predicate = expression.include?("positive?") ? "x.positive?" : "x"
      expect(subject.apply(list.first.edits)).to include("!(#{predicate})")
      expect(list.first.source).to eq("condition_negation")
      digest = ->(m) { m.digest(subject_start: subject.start_byte, original_source: subject.file_source) }
      expect(described_class.new.mutations_for(subject).map(&digest)).to eq(list.map(&digest))
    end
    subject = target("if x && x > 1; 1; else; 2; end")
    expect(subject.apply(described_class.new.mutations_for(subject).first.edits)).to include("!(x && x > 1)")
  end

  it "leaves literals existing negations loops and nested definitions alone" do
    ["if true; 1; end", "if false; 1; end", "if nil; 1; end", "if !x; 1; end", "if not x; 1; end",
     "while x; break; end", "def inner(x); 1 if x; end"].each do |expression|
      expect(described_class.new.mutations_for(target(expression))).to be_empty
    end
  end

  it "is opt-in and honors arid through builtin" do
    subject = target("1 if x")
    expect(Saboteur::MutationSource::Builtin.new.mutations_for(subject).map(&:operator))
      .not_to include("condition_negation")
    expect(Saboteur::MutationSource::Builtin.new(operators: ["condition_negation"])
      .mutations_for(subject).size).to eq(1)
    expect(Saboteur::MutationSource::Builtin.new(operators: ["condition_negation"], arid: ["x"])
      .mutations_for(subject)).to be_empty
  end

  it "deduplicates repeated proposals and rejects mutations which do not parse" do
    subject = target("1 if x")
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    expect(Saboteur::Engine::Candidates.new([described_class.new, described_class.new], diagnostics)
      .for(subject).size).to eq(1)
    mutation = described_class.new.mutations_for(subject).first
    broken = mutation.with(edits: [mutation.edits.first.with(replacement: "(")])
    source = double("source", name: "condition_negation", mutations_for: [broken])
    expect(Saboteur::Engine::Candidates.new([source], diagnostics).for(subject)).to be_empty
    expect(diagnostics.invalid_mutations).to eq(1)
  end
end
