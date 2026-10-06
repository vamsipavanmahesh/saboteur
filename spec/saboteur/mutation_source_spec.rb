# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource do
  let(:edit_class) { described_class::Edit }
  let(:mutation_class) { described_class::Mutation }

  describe "Edit" do
    it "accepts an empty range (insertion)" do
      expect(edit_class.new(file: "a.rb", start_byte: 3, end_byte: 3, replacement: "x").end_byte).to eq(3)
    end

    it "rejects a negative start" do
      expect { edit_class.new(file: "a.rb", start_byte: -1, end_byte: 0, replacement: "") }
        .to raise_error(ArgumentError, /start_byte/)
    end

    it "rejects an inverted range" do
      expect { edit_class.new(file: "a.rb", start_byte: 5, end_byte: 4, replacement: "") }
        .to raise_error(ArgumentError, /end_byte/)
    end
  end

  describe "Mutation" do
    let(:source) { "class P\n  def adult?\n    @age >= 18\n  end\nend\n" }
    let(:op_start) { source.index(">=") }
    let(:subject_start) { source.index("def") }

    def build(edit_start, replacement: ">")
      mutation_class.new(subject_id: "P#adult?", operator: "comparison",
                         edits: [edit_class.new(file: "p.rb", start_byte: edit_start,
                                                end_byte: edit_start + 2, replacement:)])
    end

    it "defaults to a fine-grained builtin mutation" do
      mutation = build(op_start)
      expect([mutation.coarse, mutation.source]).to eq([false, "builtin"])
    end

    it "requires at least one edit" do
      expect { mutation_class.new(subject_id: "P#x", operator: "o", edits: []) }
        .to raise_error(ArgumentError, /at least one edit/)
    end

    it "keeps the same digest when code above the subject shifts it" do
      shifted = "# comment\n#{source}"
      a = build(op_start).digest(subject_start:, original_source: source)
      b = build(op_start + 10).digest(subject_start: subject_start + 10, original_source: shifted)
      expect(a).to eq(b)
    end

    it "changes the digest when the replacement differs" do
      a = build(op_start).digest(subject_start:, original_source: source)
      b = build(op_start, replacement: "==").digest(subject_start:, original_source: source)
      expect(a).not_to eq(b)
    end

    it "handles multibyte text before the edit by using byte offsets" do
      text = "# héllo\n#{source}"
      start = text.b.index(">=")
      mutation = build(start)
      expect(mutation.digest(subject_start: text.b.index("def"), original_source: text))
        .to eq(build(op_start).digest(subject_start:, original_source: source))
    end
  end

  describe "Base" do
    it "requires subclasses to implement #mutations_for" do
      expect { described_class::Base.new.mutations_for(nil) }.to raise_error(NotImplementedError)
    end
  end
end
