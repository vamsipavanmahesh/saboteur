# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine::CandidateSelection do
  let(:subject_under_test) { subjects_in("class K\n  def m(a)\n    a + 1\n  end\nend\n").first }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:candidates) { instance_double(Saboteur::Engine::Candidates) }
  let(:map) { instance_double(Saboteur::Selection::CoverageMap) }
  let(:selection) { described_class.new(candidates: candidates, map: map, limit: 2, diagnostics: diagnostics) }

  it "records uncovered subjects without generating any mutants" do
    allow(map).to receive(:tests_for).with(subject_under_test).and_return([])
    expect(candidates).not_to receive(:for)
    expect(selection.for(subject_under_test)).to be_empty
    expect(selection.skipped_subjects).to eq(subject_under_test => "no coverage")
  end

  it "keeps the first candidates in deterministic coarse-first order and reports the omitted count" do
    allow(map).to receive(:tests_for).and_return(["t1"])
    list = [[:coarse, "nil"], [:coarse, "raise"], [:fine, "0"]]
    allow(candidates).to receive(:for).and_return(list)
    expect(selection.for(subject_under_test)).to eq(list.first(2))
    expect(selection.skipped_subjects).to be_empty
    expect(diagnostics.warnings).to include("K#m: omitted 1 mutant(s) above max_mutants_per_method (2)")
    expect(diagnostics.omissions).to eq([Saboteur::Engine::Diagnostics::Omission.new(subject: "K#m", count: 1,
                                                                                     limit: 2)])
  end

  it "does not warn when the candidate count equals the limit" do
    allow(map).to receive(:tests_for).and_return(["t1"])
    list = [[:coarse, "nil"], [:fine, "0"]]
    allow(candidates).to receive(:for).and_return(list)
    expect(selection.for(subject_under_test)).to eq(list)
    expect(diagnostics.warnings).to be_empty
    expect(diagnostics.omissions).to be_empty
  end

  it "restricts to changed lines before applying the limit" do
    allow(map).to receive(:tests_for).and_return(["t1"])
    list = [[:outside, "a"], [:changed, "b"], [:changed, "c"]]
    allow(candidates).to receive(:for).and_return(list)
    scope = instance_double(Saboteur::Engine::DiffScope)
    allow(scope).to receive(:restrict).with(subject_under_test, list).and_return(list.last(2))
    expect(selection.for(subject_under_test, scope: scope)).to eq(list.last(2))
    expect(diagnostics.warnings).to be_empty
    expect(diagnostics.omissions).to be_empty
  end
end

RSpec.describe Saboteur::Engine::CandidateSelection, "real candidate pipeline" do
  it "validates, deduplicates, orders coarse first, restricts the diff, then caps proposals" do
    subject = subjects_in("class K\n  def m(a)\n    a + 1\n    a + 2\n  end\nend\n").first
    source = Class.new(Saboteur::MutationSource::Base) do
      def mutations_for(subject)
        [["a + 1", "a - 1", false], ["a + 2", "a +", false],
         ["a + 2", "a + 2", false], ["a + 2", "a - 2", false],
         ["a + 2", "a - 2", false], ["a + 2", "nil", true],
         ["a + 2", "a * 2", false]].map do |original, replacement, coarse|
          start = subject.file_source.index(original)
          edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: start,
                                                    end_byte: start + original.bytesize, replacement: replacement)
          Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: replacement,
                                                 edits: [edit], coarse: coarse)
        end
      end
    end.new
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    candidates = Saboteur::Engine::Candidates.new([source, source], diagnostics)
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 4 => ["t1"] } }, tests: ["t1"])
    scope = Saboteur::Engine::DiffScope.new(subject.file => Set[4])
    selection = described_class.new(candidates: candidates, map: map, limit: 2, diagnostics: diagnostics)
    selected = selection.for(subject, scope: scope)
    expect(selected.map { |mutation, _| mutation.operator }).to eq(["nil", "a - 2"])
    expect(diagnostics.invalid_mutations).to eq(1)
    expect(diagnostics.warnings).to eq(["K#m: omitted 1 mutant(s) above max_mutants_per_method (2)"])
  end
end
