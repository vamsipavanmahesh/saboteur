# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Selection::CoverageMap, "branch selection" do
  let(:target) { subjects_in("class BranchTarget\n  def m(x)\n    x ? 10 : 20\n  end\nend\n").first }
  let(:arms) { { [3, 8, 3, 10] => ["yes"], [3, 13, 3, 15] => [] } }
  let(:map) do
    described_class.new(lines: { target.file => { 3 => %w[yes] } }, tests: %w[yes],
                        branches: { target.file => arms })
  end

  def edit(text)
    offset = target.file_source.index(text)
    Saboteur::MutationSource::Edit.new(file: target.file, start_byte: offset, end_byte: offset + text.bytesize,
                                       replacement: "0")
  end

  it "separates a taken arm from an untaken arm on the same line" do
    expect(map.tests_for_branches(target, [edit("10")])).to eq(["yes"])
    expect(map.tests_for_branches(target, [edit("20")])).to eq([])
  end

  it "does not call a multi-line arm untaken when tests ran lines inside it" do
    arms[[2, 2, 4, 5]] = []
    expect(map.tests_for_branches(target, [edit("10")])).to eq(["yes"])
  end

  it "still calls a multi-line arm untaken when tests hit only its first or last line" do
    arms[[2, 0, 4, 5]] = []
    boundary = described_class.new(lines: { target.file => { 2 => %w[yes], 4 => %w[yes] } }, tests: %w[yes],
                                   branches: { target.file => arms })
    expect(boundary.tests_for_branches(target, [edit("10")])).to eq([])
  end

  it "calls a multi-line arm no test touched untaken" do
    arms[[2, 2, 4, 5]] = []
    untouched = described_class.new(lines: {}, tests: %w[yes], branches: { target.file => arms })
    expect(untouched.tests_for_branches(target, [edit("10")])).to eq([])
  end

  it "does not let an arm that ends before the edit restrict it" do
    arms.replace({ [3, 8, 3, 10] => [], [3, 13, 3, 15] => ["yes"] })
    expect(map.tests_for_branches(target, [edit("20")])).to eq(["yes"])
  end

  it "still intersects a multi-line arm that has its own tests" do
    arms[[2, 2, 4, 5]] = ["no"]
    expect(map.tests_for_branches(target, [edit("10")])).to eq([])
  end

  it "has no branch evidence for a file the map has no arms for" do
    other = described_class.new(lines: {}, tests: %w[yes], branches: {})
    expect(other.tests_for_branches(target, [edit("10")])).to be_nil
  end

  it "leaves condition and whole-expression changes to normal selection" do
    expect(map.tests_for_branches(target, [edit("x ?")])).to be_nil
    expect(map.tests_for_branches(target, [edit("x ? 10 : 20")])).to be_nil
  end

  it "round-trips taken and zero-hit arms and preserves them with boot lines" do
    restored = described_class.from_json(map.with_load_lines(target.file => [2]).to_json)
    expect(restored.branches).to eq(map.branches)
    expect(restored.tests_for_branches(target, [edit("20")])).to eq([])
  end

  it "intersects nested arms rather than crediting an outer hit alone" do
    arms[[3, 4, 3, 15]] = ["yes"]
    expect(map.tests_for_branches(target, [edit("20")])).to eq([])
  end

  it "unions separate edited arms, and keeps line selection for an unrestricted edit" do
    arms[[3, 13, 3, 15]] = ["no"]
    expect(map.tests_for_branches(target, [edit("10"), edit("20")])).to eq(%w[yes no])
    expect(map.tests_for_branches(target, [edit("10"), edit("x ?")])).to be_nil
  end

  it "uses byte columns when a multibyte character precedes the arm" do
    source = target.file_source.sub("x ?", '"é"; x ?')
    subject = subjects_in(source).first
    at = source.b.index("20")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2,
                                              replacement: "0")
    line_start = source.b.rindex("\n", at) + 1
    span = [3, at - line_start, 3, at - line_start + 2]
    map = described_class.new(lines: {}, tests: [], branches: { subject.file => { span => [] } })
    expect(map.tests_for_branches(subject, [edit])).to eq([])
  end
  it "accepts strictly interior edits and rejects edits crossing an arm boundary" do
    arms.clear
    arms[[3, 7, 3, 11]] = ["yes"]
    expect(map.tests_for_branches(target, [edit("1")])).to eq(["yes"])
    expect(map.tests_for_branches(target, [edit("0 :")])).to be_nil
  end

  it "computes first-line and later-line byte positions" do
    expect(map.send(:position, "abc\ndef", 0)).to eq([1, 0])
    expect(map.send(:position, "abc\ndef", 2)).to eq([1, 2])
    expect(map.send(:position, "abc\ndef", 4)).to eq([2, 0])
    expect(map.send(:position, "é\ndef", 3)).to eq([2, 0])
  end
  it "invalidates older-format caches that have no branch evidence" do
    document = JSON.parse(map.to_json)
    document["format"] = described_class::FORMAT - 1
    document.delete("branches")
    expect { described_class.from_json(JSON.generate(document)) }
      .to raise_error(Saboteur::Error, /format #{described_class::FORMAT - 1} is not #{described_class::FORMAT}/)
  end
end
