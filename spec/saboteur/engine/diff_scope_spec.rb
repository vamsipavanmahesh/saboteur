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

  it "keeps nothing fine when no line of the method changed" do
    expect(kept_lines([99])).to be_empty
  end
end
