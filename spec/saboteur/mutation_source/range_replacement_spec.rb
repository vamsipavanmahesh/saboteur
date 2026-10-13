# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::RangeReplacement do
  def target(expression)
    subjects_in("class RangeTarget\n  def m\n    #{expression}\n  end\nend\n").first
  end

  it "handles a method with no body" do
    expect(described_class.new.mutations_for(target(""))).to be_empty
  end

  it "swaps either bounded endpoint rule deterministically" do
    { "1..3" => "1...3", "1...3" => "1..3" }.each do |before, after|
      subject = target(before)
      mutations = described_class.new.mutations_for(subject)
      expect(mutations.size).to eq(1)
      expect(subject.apply(mutations.first.edits)).to include(after)
      digests = lambda {
        described_class.new.mutations_for(subject).map do |mutation|
          mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
        end
      }
      expect(digests.call).to eq(digests.call)
    end
  end

  it "leaves endpointless ranges and arid expressions alone" do
    expect(described_class.new.mutations_for(target("1.."))).to be_empty
    expect(described_class.new.mutations_for(target("..3"))).to be_empty
    expect(described_class.new(arid: ["1"]).mutations_for(target("1..3"))).to be_empty
  end

  it "passes valid mutations through the parser and drops invalid proposals" do
    subject = target("1..3")
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    candidates = Saboteur::Engine::Candidates.new([described_class.new], diagnostics)
    expect(candidates.for(subject).size).to eq(1)
    mutation = described_class.new.mutations_for(subject).first
    edit = mutation.edits.first.with(replacement: "(")
    broken = mutation.with(edits: [edit])
    source = double("source", name: "range", mutations_for: [broken])
    expect(Saboteur::Engine::Candidates.new([source], diagnostics).for(subject)).to be_empty
    expect(diagnostics.invalid_mutations).to eq(1)
  end
  it "is opt-in and passes arid through builtin wiring without changing default operators" do
    subject = target("1..3")
    expect(Saboteur::MutationSource::Builtin.new.mutations_for(subject).map(&:operator)).not_to include("range")
    expect(Saboteur::MutationSource::Builtin.new(operators: ["range"]).mutations_for(subject).map(&:operator))
      .to eq(["range"])
    expect(Saboteur::MutationSource::Builtin.new(operators: ["range"], arid: ["1"])
      .mutations_for(subject)).to be_empty
    expect(Saboteur::MutationSource::Builtin.new(operators: ["range"], arid: []).mutations_for(subject))
      .not_to be_empty
  end

  it "deduplicates the same edit from multiple sources" do
    subject = target("1..3")
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    expect(Saboteur::Engine::Candidates.new([described_class.new, described_class.new], diagnostics)
      .for(subject).size).to eq(1)
  end
  it "does not enter nested definitions and labels its source explicitly" do
    subject = target("def inner; 1..3; end; 1..2")
    mutations = described_class.new.mutations_for(subject)
    expect(mutations.size).to eq(1)
    expect(mutations.first.source).to eq("range")
    expect(mutations.first.operator).to eq("range")
  end
end
