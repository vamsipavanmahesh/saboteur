# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::DiffScope do
  let(:subject_under_test) do
    subjects_in("class K\n  def m(a)\n    b = a + 1\n    c = b * 2\n    c - 3\n  end\nend\n").first
  end
  let(:candidates) do
    Saboteur::MutationSource::Builtin.new.mutations_for(subject_under_test).map do |mutation|
      [mutation, subject_under_test.apply(mutation.edits)]
    end
  end

  def scope(lines)
    described_class.new({ subject_under_test.file => Set.new(lines) })
  end

  def kept_lines(lines)
    scope(lines).restrict(subject_under_test, candidates).reject { |mutation, _| mutation.coarse }.map do |mutation, _|
      subject_under_test.file_source.byteslice(0, mutation.edits.first.start_byte).count("\n") + 1
    end.uniq
  end

  it "keeps fine mutants only on changed lines" do
    expect(kept_lines([4])).to eq([4])
  end

  it "always keeps the coarse mutants of a changed method" do
    kept = scope([4]).restrict(subject_under_test, candidates)
    expect(kept.select { |mutation, _| mutation.coarse }.map { |mutation, _| mutation.operator })
      .to eq(%w[body_nil body_raise])
  end

  it "keeps the coarse mutants even when only the def line changed" do
    kept = scope([2]).restrict(subject_under_test, candidates)
    expect(kept.map { |mutation, _| mutation.operator }).to eq(%w[body_nil body_raise])
  end

  it "keeps nothing fine when no line of the method changed" do
    expect(kept_lines([99])).to be_empty
  end

  describe "#changed_lines_for" do
    def mutation_at(text, replacement: "x")
      start = subject_under_test.file_source.index(text)
      edit = Saboteur::MutationSource::Edit.new(file: subject_under_test.file, start_byte: start,
                                                end_byte: start + text.bytesize, replacement:)
      Saboteur::MutationSource::Mutation.new(subject_id: subject_under_test.id, operator: "test", edits: [edit])
    end

    it "names the changed line a mutant touches" do
      expect(scope([4]).changed_lines_for(subject_under_test, mutation_at("b * 2"))).to eq([4])
    end

    it "returns nothing for a mutant on an unchanged line" do
      expect(scope([5]).changed_lines_for(subject_under_test, mutation_at("b * 2"))).to eq([])
    end

    it "names the changed line below the first line of a mutated multi-line statement" do
      mutation = mutation_at("b = a + 1\n    c = b * 2")
      expect(scope([4, 99]).changed_lines_for(subject_under_test, mutation)).to eq([4])
    end

    it "returns nothing for a file with no changed lines" do
      other = described_class.new({})
      expect(other.changed_lines_for(subject_under_test, mutation_at("b * 2"))).to eq([])
    end
  end
end
