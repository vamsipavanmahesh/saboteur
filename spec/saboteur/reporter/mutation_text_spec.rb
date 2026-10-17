# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Reporter::MutationText do
  let(:source) do
    <<~RUBY
      class Sample
        def run
          first = 1
          second = 2
        end
      end
    RUBY
  end
  let(:target) { subjects_in(source).first }

  def edit(text, replacement)
    at = target.file_source.index(text)
    Saboteur::MutationSource::Edit.new(file: target.file, start_byte: at, end_byte: at + text.size, replacement:)
  end

  def result_with(*edits)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: target.id, operator: "x", edits: edits,
                                                      coarse: false)
    Saboteur::MutantResult.new(subject: target, mutation:, status: :survived, mutated_source: target.apply(edits))
  end

  it "reports the line of the first edit in source order, however the edits were given" do
    result = result_with(edit("second = 2", "a"), edit("first = 1", "b"))
    expect(described_class.line(result)).to eq(3)
  end

  it "knows a removal-only mutant from one with a replacement (#502)" do
    expect(described_class.removal?(result_with(edit("first = 1", ""), edit("second = 2", "")))).to be(true)
    expect(described_class.removal?(result_with(edit("first = 1", ""), edit("second = 2", "2")))).to be(false)
    expect(described_class.removal?(result_with(edit("first = 1", "one")))).to be(false)
  end

  it "joins the edits in source order with a pipe" do
    result = result_with(edit("second = 2", "B"), edit("first = 1", "A"))
    expect(described_class.original(result)).to eq("first = 1 | second = 2")
    expect(described_class.replacement(result)).to eq("A | B")
  end

  it "folds line breaks and indentation into one space and trims the ends" do
    expect(described_class.replacement(result_with(edit("first = 1", "  a\n    b \n c  ")))).to eq("a b c")
  end

  it "keeps a 60 character text whole" do
    text = "a" * 60
    expect(described_class.replacement(result_with(edit("first = 1", text)))).to eq(text)
  end

  it "cuts a 61 character text to 57 characters and an ellipsis" do
    expect(described_class.replacement(result_with(edit("first = 1", "a" * 61)))).to eq("#{'a' * 57}...")
    expect(described_class.replacement(result_with(edit("first = 1", ("a".."z").to_a.join * 3)))).to eq(
      "#{('a'..'z').to_a.join * 2}#{('a'..'z').first(5).join}..."
    )
  end
end
