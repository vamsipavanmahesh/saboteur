# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../../bench/research/pattern_equivalence/matcher"

RSpec.describe PatternEquivalence::Matcher do
  let(:matcher) { described_class.new }

  def matched(body)
    subject = subjects_in("class Probe; def call(value); #{body}; end; end").first
    Saboteur::MutationSource::Builtin.new.mutations_for(subject).filter_map do |mutation|
      pattern = matcher.classify(subject, mutation)
      [pattern, subject.apply(mutation.edits)] if pattern
    end
  end

  it "recognizes a directly supplied byte-identical edit as P0 without calling it a useful skip" do
    subject = subjects_in("class Probe; def call; 1; end; end").first
    offset = subject.file_source.index("1")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: offset, end_byte: offset + 1,
                                              replacement: "1")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "noop", edits: [edit])
    expect(matcher.classify(subject, mutation)).to eq("P0_noop")
  end

  it "recognizes left literal truth identities without dropping evaluation of the right operand" do
    expect(matched("true && value")).to eq([["P6_left_identity", "def call(value); value; end"]])
    expect(matched("false || value")).to eq([["P6_left_identity", "def call(value); value; end"]])
  end

  it "does not assume a local read is pure or use boolean equivalence for return values" do
    ["value && true", "value || false", "value && false", "value || true", "value && value",
     "value || value"].each do |body|
      expect(matched(body)).to be_empty
    end
  end

  it "does not infer runtime types or skip comparisons, navigation or arithmetic" do
    ["value&.size", "value * 1", "value < 1", "value ||= 1"].each { |body| expect(matched(body)).to be_empty }
  end
end
