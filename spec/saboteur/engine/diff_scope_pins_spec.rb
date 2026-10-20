# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::DiffScope, "pins" do
  let(:subject_under_test) do
    subjects_in("class K\n  def m(a)\n    b = a + 1\n    c = b * 2\n    c - 3\n  end\nend\n").first
  end

  def scope(lines)
    described_class.new({ subject_under_test.file => Set.new(lines) })
  end

  def mutation_at(text, replacement: "x", width: text.bytesize)
    start = subject_under_test.file_source.index(text)
    edit = Saboteur::MutationSource::Edit.new(file: subject_under_test.file, start_byte: start,
                                              end_byte: start + width, replacement:)
    Saboteur::MutationSource::Mutation.new(subject_id: subject_under_test.id, operator: "test", edits: [edit])
  end

  it "does not count the next line when an edit ends on its first byte" do
    mutation = mutation_at("b = a + 1\n")
    expect(scope([4]).changed_lines_for(subject_under_test, mutation)).to eq([])
    expect(scope([3]).changed_lines_for(subject_under_test, mutation)).to eq([3])
    expect(scope([4]).distance_for(subject_under_test, mutation)).to eq(1)
    expect(scope([4]).restrict(subject_under_test, [[mutation, ""]])).to be_empty
  end

  it "puts a zero-width insertion on the line it is made in" do
    insertion = mutation_at("    c = b * 2", replacement: "x", width: 0)
    expect(scope([4]).changed_lines_for(subject_under_test, insertion)).to eq([4])
    expect(scope([3]).changed_lines_for(subject_under_test, insertion)).to eq([])
    expect(scope([4]).distance_for(subject_under_test, insertion)).to eq(0)
  end

  it "measures from the nearest end of a multi-line edit to a changed set of lines" do
    mutation = mutation_at("b = a + 1\n    c = b * 2")
    expect(scope([5]).distance_for(subject_under_test, mutation)).to eq(1)
    expect(scope([2]).distance_for(subject_under_test, mutation)).to eq(1)
    expect(scope([3, 5]).distance_for(subject_under_test, mutation)).to eq(0)
  end
end
