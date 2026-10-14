# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::OperatorAssignment do
  def target(expression)
    subjects_in("class AssignmentTarget\n  def m(a)\n    #{expression}\n  end\nend\n").first
  end

  it "handles a method with no body" do
    expect(described_class.new.mutations_for(target(""))).to be_empty
  end

  it "swaps each arithmetic compound assignment deterministically" do
    { "a += 1" => "a -= 1", "a -= 1" => "a += 1", "a *= 2" => "a /= 2", "a /= 2" => "a *= 2" }.each do |before, after|
      subject = target(before)
      mutations = described_class.new.mutations_for(subject)
      expect(mutations.size).to eq(1)
      expect(subject.apply(mutations.first.edits)).to include(after)
      digest = ->(m) { m.digest(subject_start: subject.start_byte, original_source: subject.file_source) }
      expect(described_class.new.mutations_for(subject).map(&digest)).to eq(mutations.map(&digest))
      expect(mutations.first.source).to eq("operator_assignment")
    end
  end

  it "preserves instance class global constant call and index targets" do
    %w[@a @@a $a A A::B a.x a[0]].each do |receiver|
      subject = target("#{receiver} += 1")
      list = described_class.new.mutations_for(subject)
      expect(list.size).to eq(1), receiver
      expect(subject.apply(list.first.edits)).to include("#{receiver} -= 1")
    end
  end

  it "leaves other assignments, nested definitions and arid expressions alone" do
    ["a = 1", "a ||= 1", "a &&= 1", "a %= 2", "def inner; a += 1; end"].each do |expression|
      expect(described_class.new.mutations_for(target(expression))).to be_empty
    end
    expect(described_class.new(arid: ["a"]).mutations_for(target("a += 1"))).to be_empty
  end

  it "is default-on and wires arid through builtin" do
    subject = target("a += 1")
    expect(Saboteur::MutationSource::Builtin.new.mutations_for(subject).map(&:operator))
      .to include("operator_assignment")
    expect(Saboteur::MutationSource::Builtin.new(operators: ["operator_assignment"])
      .mutations_for(subject).size).to eq(1)
    expect(Saboteur::MutationSource::Builtin.new(operators: ["operator_assignment"], arid: ["a"])
      .mutations_for(subject)).to be_empty
  end

  it "deduplicates repeated proposals and rejects mutations which do not parse" do
    subject = target("a += 1")
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    expect(Saboteur::Engine::Candidates.new([described_class.new, described_class.new], diagnostics)
      .for(subject).size).to eq(1)
    mutation = described_class.new.mutations_for(subject).first
    broken = mutation.with(edits: [mutation.edits.first.with(replacement: "(")])
    source = double("source", name: "operator_assignment", mutations_for: [broken])
    expect(Saboteur::Engine::Candidates.new([source], diagnostics).for(subject)).to be_empty
    expect(diagnostics.invalid_mutations).to eq(1)
  end
end
