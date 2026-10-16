# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "timeout"

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

  def mutation_at(text, replacement: "x")
    start = subject_under_test.file_source.index(text)
    edit = Saboteur::MutationSource::Edit.new(file: subject_under_test.file, start_byte: start,
                                              end_byte: start + text.bytesize, replacement:)
    Saboteur::MutationSource::Mutation.new(subject_id: subject_under_test.id, operator: "test", edits: [edit])
  end

  def mutation_with(*texts)
    edits = texts.flat_map { |text| mutation_at(text).edits }
    Saboteur::MutationSource::Mutation.new(subject_id: subject_under_test.id, operator: "test", edits:)
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

  it "keeps a multi-edit mutant when any single edit touches a changed line" do
    both = mutation_with("c = b * 2", "class K")
    expect(scope([4]).restrict(subject_under_test, [[both, ""]]).map { |mutation, _| mutation }).to eq([both])
  end

  it "keeps a mutant whose multi-line edit touches the changed line anywhere" do
    wide = mutation_at("b = a + 1\n    c = b * 2")
    expect(scope([4]).restrict(subject_under_test, [[wide, ""]]).map { |mutation, _| mutation }).to eq([wide])
  end

  describe "#distance_for" do
    def range_scope(range)
      described_class.new({ subject_under_test.file => range })
    end

    it "is zero when the edit overlaps the range" do
      expect(range_scope(1..7).distance_for(subject_under_test, mutation_at("class K"))).to eq(0)
      expect(range_scope(4..4).distance_for(subject_under_test, mutation_at("c = b * 2"))).to eq(0)
    end

    it "is the gap to the nearer endpoint when the edit misses the range" do
      expect(range_scope(4..6).distance_for(subject_under_test, mutation_at("class K"))).to eq(3)
      expect(range_scope(1..3).distance_for(subject_under_test, mutation_at("c - 3"))).to eq(2)
    end

    it "does not enumerate a huge range" do
      huge = Class.new(Range) do
        def each(*) = raise("enumerated a huge range")

        def map(*) = raise("enumerated a huge range")

        def any?(*) = raise("enumerated a huge range")
      end.new(1, 10**15)
      Timeout.timeout(5) do
        expect(range_scope(huge).distance_for(subject_under_test, mutation_at("class K"))).to eq(0)
      end
    end

    it "is the nearest changed line when the lines are a set" do
      expect(scope([1, 3]).distance_for(subject_under_test, mutation_at("c - 3"))).to eq(2)
    end

    it "is the nearest edit when a mutation edits twice" do
      both = mutation_with("class K", "c - 3")
      expect(scope([6]).distance_for(subject_under_test, both)).to eq(1)
    end
  end

  describe "#changed_lines_for" do
    it "names the changed line a mutant touches" do
      expect(scope([4]).changed_lines_for(subject_under_test, mutation_at("b * 2"))).to eq([4])
    end

    it "returns nothing for a mutant on an unchanged line" do
      expect(scope([5]).changed_lines_for(subject_under_test, mutation_at("b * 2"))).to eq([])
    end

    it "names each changed line once when two edits touch it" do
      both = mutation_with("c = b * 2", "b * 2")
      expect(scope([4]).changed_lines_for(subject_under_test, both)).to eq([4])
    end

    it "counts an edit ending on the next line's first byte as touching that line" do
      mutation = mutation_at("b = a + 1\n ")
      expect(scope([4]).changed_lines_for(subject_under_test, mutation)).to eq([4])
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
