# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/mutation_source/argument_swap"

RSpec.describe Saboteur::MutationSource::ArgumentSwap do
  let(:source) { described_class.new(arid: ["logger"]) }

  def subject_for(body)
    subjects_in("# héllo\nclass SwapExample\n def choose(a, b)\n #{body}\n end\nend").first
  end

  it "swaps two positional arguments and an order-sensitive assertion kills it" do
    subject = subject_for("a.fetch(b, :fallback)")
    mutation = source.mutations_for(subject).fetch(0)
    correct = Class.new { class_eval(subject.source) }.new
    changed = Class.new { class_eval(subject.apply(mutation.edits)) }.new
    input = { key: :value, fallback: :other }
    expect(correct.choose(input, :key)).to eq(:value)
    expect { expect(changed.choose(input, :key)).to eq(:value) }
      .to raise_error(RSpec::Expectations::ExpectationNotMetError)
    expect(mutation.operator).to eq("argument_swap")
    expect(mutation.source).to eq("argument_swap")
    expect(mutation.coarse).to be(false)
    expect(Saboteur::MutationSource::OperatorRegistry.list(StringIO.new)).to be_nil
  end

  it "swaps operator-call arguments whose opening location is nil without raising" do
    subject = subject_for("a.fetch(b + c, d)")
    found = source.mutations_for(subject)
    expect(found.size).to eq(1)
    expect(subject.apply(found.first.edits)).to include("a.fetch(d, b + c)")
  end

  it "preserves comments, whitespace, safe navigation, trailing commas and byte offsets" do
    subject = subject_for("a&.fetch( b, # keep\n :fallback, )")
    changed = subject.apply(source.mutations_for(subject).fetch(0).edits)
    expect(changed).to include("a&.fetch( :fallback, # keep\n b, )")
    expect(Prism.parse(changed).success?).to be(true)
  end

  it "rejects unsupported shapes, identical arguments, arid and nested definitions" do
    ["a.fetch()", "a.fetch(b)", "a.fetch(b, 1, 2)", "a.fetch(*b, 1)", "a.fetch(b, key: 1)",
     "a.fetch(b, b)", "logger.info(a, b)", "def inner; a.fetch(b, 1); end",
     "a.fetch b, 1", "a[ b, 1 ]", "a.fetch([<<~TEXT], b)\nhi\nTEXT", "a.fetch(b, <<~TEXT)\nhi\nTEXT"].each do |body|
      expect(source.mutations_for(subject_for(body))).to be_empty, body
    end
  end

  it "keeps an attached block, walks nested calls, and obeys builtin selection and exclusion" do
    subject = subject_for("a.fetch(b, pair(1, 2)) { :missing }")
    found = source.mutations_for(subject)
    expect(found.size).to eq(2)
    expect(subject.apply(found.first.edits)).to include("a.fetch(pair(1, 2), b) { :missing }")
    builtin = Saboteur::MutationSource::Builtin
    expect(builtin.new(operators: ["argument_swap"]).mutations_for(subject)).to eq(found)
    expect(builtin.new(exclude_operators: ["argument_swap"]).mutations_for(subject).map(&:operator))
      .not_to include("argument_swap")
    expect(builtin.new(operators: ["argument_swap"], arid: ["fetch"]).mutations_for(subject)).to be_empty
  end
end
