# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/method_swap"

RSpec.describe Saboteur::MutationSource::MethodSwap do
  let(:source) { described_class.new(arid: Saboteur::MutationSource::Builtin::DEFAULT_ARID) }

  def subject_for(body)
    subjects_in("class SwapExample\n  def pick(xs)\n    #{body}\n  end\nend\n").first
  end

  def replacements(body)
    subject = subject_for(body)
    source.mutations_for(subject).map { |mutation| subject.apply(mutation.edits) }
  end

  it "skips arid expressions and nested definitions per the documented skip contract" do
    expect(replacements("def inner; xs.min { |x| x }; end")).to be_empty
    expect(described_class.new(arid: ["min"]).mutations_for(subject_for("xs.min { |x| x }"))).to be_empty
  end

  { "min" => "max", "max" => "min", "any?" => "all?", "all?" => "any?", "map" => "each",
    "each" => "map" }.each do |original, replacement|
    it "swaps #{original} with #{replacement}" do
      subject = subject_for("xs.#{original} { |x| x }")
      mutation = source.mutations_for(subject).fetch(0)
      expect(mutation.operator).to eq("method_swap")
      expect(mutation.coarse).to be(false)
      expect(mutation.source).to eq("method_swap")
      expect(subject.apply(mutation.edits)).to include("xs.#{replacement} { |x| x }")
    end
  end

  it "changes only the message bytes: receiver, arguments, block and safe navigation stay" do
    expect(replacements("xs&.min(2)")).to eq(["def pick(xs)\n    xs&.max(2)\n  end"])
  end

  it "requires a receiver, so a bare Kernel max(a, b) call is untouched" do
    expect(replacements("max(a, b)")).to be_empty
  end

  it "leaves other methods alone" do
    expect(replacements("xs.first")).to be_empty
    expect(replacements("xs.select { |x| x }")).to be_empty
  end

  it "produces a mutant an output assertion kills" do
    subject = subject_for("xs.min")
    mutation = source.mutations_for(subject).fetch(0)
    correct = Class.new { class_eval(subject.source) }.new
    changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
    expect(correct.pick([1, 2, 3])).to eq(1)
    expect { expect(changed.pick([1, 2, 3])).to eq(1) }
      .to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it "keeps the digest stable after a multibyte comment above the method" do
    plain = subject_for("xs.min")
    shifted = subjects_in("# héllo\nclass SwapExample\n  def pick(xs)\n    xs.min\n  end\nend\n").first
    digests = [plain, shifted].map do |subject|
      source.mutations_for(subject).fetch(0).digest(subject_start: subject.start_byte,
                                                    original_source: subject.file_source)
    end
    expect(digests.uniq.size).to eq(1)
  end
  it "descends into nested expressions like an if body" do
    expect(replacements("if flag\n      xs.min { |x| x }\n    end")).not_to be_empty
  end

  it "treats a statement matching any one arid pattern as arid" do
    expect(described_class.new(arid: %w[min zzz]).mutations_for(subject_for("xs.min { |x| x }"))).to be_empty
  end
end
