# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::OperatorExplain do
  names = Saboteur::MutationSource::OperatorRegistry::DESCRIPTIONS.keys

  it "has an entry for every operator the registry can emit" do
    names.each do |name|
      expect(described_class.for(name)).not_to be_nil, "operator #{name} ships without an explain entry"
    end
  end

  it "carries no stale entries for removed operators" do
    expect(described_class::GUIDANCE.keys - names).to be_empty
  end

  it "returns nil for an unknown name, so the command can print the valid list" do
    expect(described_class.for("not_an_operator")).to be_nil
  end

  names.each do |name|
    it "shares the --list-operators wording for #{name}" do
      entry = described_class.for(name)
      expect(entry.definition).to eq(Saboteur::MutationSource::OperatorRegistry::DESCRIPTIONS.fetch(name))
      expect(entry.example).to eq(Saboteur::MutationSource::OperatorExamples::EXAMPLES.fetch(name))
    end
  end

  it "fills every field for every entry" do
    names.each do |name|
      entry = described_class.for(name)
      expect(entry.survives).to match(/\S/), name
      expect(entry.kill).to match(/\S/), name
      expect(entry.example.split(" -> ").size).to eq(2), name
    end
  end
end
