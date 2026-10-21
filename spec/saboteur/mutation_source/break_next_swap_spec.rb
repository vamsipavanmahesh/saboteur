# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/break_next_swap"

RSpec.describe Saboteur::MutationSource::BreakNextSwap do
  let(:source) { described_class.new }

  def subject_for(body)
    subjects_in("class SwapExample\n  def walk(xs)\n    #{body}\n  end\nend\n").first
  end

  def replacements(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits).lines[1..-2].join.strip }
  end

  it "swaps break for next, keeping the value" do
    expect(replacements("xs.each { |x| break x }")).to eq(["xs.each { |x| next x }"])
  end

  it "swaps next for break, bare and with a value" do
    expect(replacements("xs.each { |x| next }")).to eq(["xs.each { |x| break }"])
    expect(replacements("xs.each { |x| next x }")).to eq(["xs.each { |x| break x }"])
  end

  it "swaps a bare break" do
    expect(replacements("loop { break }")).to eq(["loop { next }"])
  end

  it "swaps each jump on its own" do
    expect(replacements("xs.each { |x| next if x\n    break }"))
      .to eq(["xs.each { |x| break if x\n    break }", "xs.each { |x| next if x\n    next }"])
  end

  it "leaves return and other statements alone" do
    expect(replacements("return 1")).to be_empty
    expect(replacements("x = 1")).to be_empty
  end

  it "names its operator and source" do
    expect(subject_for("loop { break }").then do |subject|
      source.mutations_for(subject).map do |m|
        [m.operator, m.source]
      end.uniq
    end)
      .to eq([%w[break_next_swap break_next_swap]])
  end

  it "skips arid statements" do
    skip_source = described_class.new(arid: ["loop"])
    subject = subject_for("loop { break }")
    expect(skip_source.mutations_for(subject)).to be_empty
    expect(source.mutations_for(subject)).not_to be_empty
  end
end
