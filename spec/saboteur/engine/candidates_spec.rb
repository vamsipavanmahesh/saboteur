# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::Candidates do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:subject_under_test) { subjects_in("class K\n  def m(a)\n    a + 1\n  end\nend\n").first }

  # A mutation source that proposes whatever replacements it is given for
  # the `a + 1` expression.
  def source_proposing(*replacements, coarse: false)
    owner = subject_under_test
    Class.new(Saboteur::MutationSource::Base) do
      define_method(:mutations_for) do |subject|
        at = subject.file_source.index("a + 1")
        replacements.map do |text|
          edit = Saboteur::MutationSource::Edit.new(file: owner.file, start_byte: at, end_byte: at + 5,
                                                    replacement: text)
          Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit],
                                                 coarse: coarse)
        end
      end
    end.new
  end

  def candidates(*sources)
    described_class.new(sources, diagnostics).for(subject_under_test)
  end

  it "applies each mutation and returns the mutated method text" do
    expect(candidates(source_proposing("a - 1")).map(&:last)).to eq(["def m(a)\n    a - 1\n  end"])
  end

  it "drops mutations that change nothing or repeat an earlier one" do
    expect(candidates(source_proposing("a + 1", "a - 1", "a - 1")).size).to eq(1)
  end

  it "drops and counts mutations that do not parse" do
    expect(candidates(source_proposing("a +"))).to be_empty
    expect(diagnostics.invalid_mutations).to eq(1)
  end

  it "puts coarse mutations first" do
    found = candidates(source_proposing("a - 1"), source_proposing("nil", coarse: true))
    expect(found.map { |mutation, _| mutation.coarse }).to eq([true, false])
  end

  it "drops a mutation with an edit outside the method and warns" do
    outside = Class.new(Saboteur::MutationSource::Base) do
      define_method(:mutations_for) do |subject|
        edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: 0, end_byte: 5, replacement: "x")
        [Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "bad", edits: [edit])]
      end
    end.new
    expect(candidates(outside)).to be_empty
    expect(diagnostics.warnings.first).to include("outside")
  end

  describe ".build_sources (external)" do
    it "loads a namespaced source class from a file" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "deep.rb"),
                   "module DeepSources\n  class One < Saboteur::MutationSource::Base\n  end\nend\n")
        config = Saboteur::Config.new({ "sources" => ["deep.rb:DeepSources::One"] }, root: dir)
        expect(described_class.build_sources(config).first).to be_a(DeepSources::One)
      end
    end
  end

  describe ".build_sources" do
    it "builds the builtin source and rejects an entry without a class name" do
      config = Saboteur::Config.new({ "sources" => ["builtin"] })
      expect(described_class.build_sources(config).map(&:name)).to eq(["builtin"])
      bad = Saboteur::Config.new({ "sources" => ["lib/my_source.rb"] })
      expect { described_class.build_sources(bad) }.to raise_error(Saboteur::ConfigError, /path.rb:ClassName/)
    end
  end
end
