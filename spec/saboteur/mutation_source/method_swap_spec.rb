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
  # #399: each and map run the block the same way and differ only in the
  # return value. When the call's value is provably discarded - a non-last
  # statement - the swap is an equivalent mutant, so it is not emitted.
  describe "statement-position each/map swap suppression (#399)" do
    it "does not swap each in a non-last statement (return discarded)" do
      expect(replacements("xs.each { |x| log(x) }\n    xs.sum")).to be_empty
    end

    it "does not swap map in a non-last statement (return discarded)" do
      expect(replacements("xs.map { |x| log(x) }\n    xs.sum")).to be_empty
    end

    it "still swaps each in return position, where the value is used" do
      expect(replacements("xs.each { |x| log(x) }")).to eq(["def pick(xs)\n    xs.map { |x| log(x) }\n  end"])
    end

    it "still swaps each when the value is assigned" do
      expect(replacements("collected = xs.each { |x| log(x) }")).not_to be_empty
    end

    it "still swaps any? in a non-last statement: early-stop sides differ" do
      expect(replacements("xs.any? { |x| log(x) }\n    xs.sum")).not_to be_empty
    end

    # A lazy receiver changes everything: lazy.map never runs the block
    # (the value is discarded AND the enumeration is deferred), so each ->
    # map on it drops the side effects - not an equivalent mutant (#431).
    it "still swaps each in a non-last statement on a lazy receiver (#431)" do
      expect(replacements("xs.lazy.each { |x| log(x) }
    xs.sum")).not_to be_empty
    end

    it "still swaps map in a non-last statement on a lazy receiver (#431)" do
      expect(replacements("xs.lazy.map { |x| log(x) }.force
    xs.sum")).not_to be_empty
    end

    it "still swaps each in a non-last statement when lazy is deeper in the chain (#431)" do
      expect(replacements("xs.lazy.select { |x| x }.each { |x| log(x) }
    xs.sum")).not_to be_empty
    end

    it "still swaps min in a non-last statement (out of #399's scope)" do
      expect(replacements("xs.min { |x| x }\n    xs.sum")).not_to be_empty
    end
  end

  # A branch's value is the value of its last statement, so when the branch
  # container's own value is discarded, each/map calls in that tail position
  # are discard-equivalent too. Propagate the discarded-value context through
  # branch bodies (#440), while any call whose value flows into a condition,
  # receiver, block result, or control-flow argument stays swappable.
  describe "branch-tail each/map swap suppression (#440)" do
    it "does not swap each as the tail of a discarded if branch" do
      expect(replacements("if ready?\n      xs.each { |x| log(x) }\n    end\n    xs.sum")).to be_empty
    end

    it "does not swap map as the tail of a discarded else branch" do
      expect(replacements(
               "if ready?\n      log(:a)\n    else\n      xs.map { |x| log(x) }\n    end\n    xs.sum"
             )).to be_empty
    end

    it "does not swap each as the tail of a discarded elsif branch" do
      expect(replacements(
               "if ready?\n      log(:a)\n    elsif other?\n      xs.each { |x| log(x) }\n    end\n    xs.sum"
             )).to be_empty
    end

    it "does not swap each as the tail of a discarded when branch" do
      expect(replacements("case tag\n    when :a\n      xs.each { |x| log(x) }\n    end\n    xs.sum")).to be_empty
    end

    it "does not swap map as the tail of a discarded case else branch" do
      expect(replacements(
               "case tag\n    when :a\n      log(:a)\n    else\n      xs.map { |x| log(x) }\n    end\n    xs.sum"
             )).to be_empty
    end

    it "does not swap each as the body of a discarded modifier if" do
      expect(replacements("xs.each { |x| log(x) } if ready?\n    xs.sum")).to be_empty
    end

    it "does not swap each inside a discarded while body: the loop value never observes it" do
      expect(replacements("while ready?\n      xs.each { |x| log(x) }\n    end")).to be_empty
    end

    it "does not swap each/map as branch tails of a discarded begin/rescue" do
      body = [
        "begin",
        "  xs.each { |x| log(x) }",
        "rescue StandardError",
        "  ys.map { |y| y }",
        "end",
        "xs.sum"
      ].join("\n    ")
      expect(replacements(body)).to be_empty
    end

    it "does not swap each as the tail of nested discarded branches" do
      expect(replacements(
               "if ready?\n      if other?\n        xs.each { |x| log(x) }\n      end\n    end\n    xs.sum"
             )).to be_empty
    end

    it "still swaps each in a discarded if's predicate: the value selects the branch" do
      expect(replacements("if xs.each { |x| x }\n      log(:a)\n    end\n    xs.sum")).not_to be_empty
    end

    it "still swaps each as a block result in a discarded statement" do
      expect(replacements("run { xs.each { |x| x } }\n    xs.sum")).not_to be_empty
    end

    it "still swaps each as a receiver in a discarded statement" do
      expect(replacements("xs.each { |x| x }.sum\n    xs.sum")).not_to be_empty
    end

    it "still swaps each as a return argument inside a discarded branch" do
      expect(replacements("if ready?\n      return xs.each { |x| x }\n    end\n    xs.sum")).not_to be_empty
    end

    it "still swaps each as a break argument inside a while body" do
      expect(replacements("while ready?\n      break xs.each { |x| x }\n    end")).not_to be_empty
    end

    it "still swaps each as the branch tail when the if's value is used" do
      expect(replacements("if ready?\n      xs.each { |x| log(x) }\n    end")).not_to be_empty
    end

    it "does not swap each in an ensure body: the value never contributes to the result" do
      expect(replacements(
               "begin\n      log(:a)\n    ensure\n      xs.each { |x| log(x) }\n    end\n    xs.sum"
             )).to be_empty
      expect(replacements("begin\n      log(:a)\n    ensure\n      xs.each { |x| log(x) }\n    end")).to be_empty
    end

    it "does not swap each as the tail of a discarded in branch (case/in)" do
      expect(replacements("case tag\n    in [head, *]\n      xs.each { |x| log(x) }\n    end\n    xs.sum")).to be_empty
    end

    it "does not swap map as the tail of a discarded case/in else branch" do
      expect(replacements(
               "case tag\n    in [head, *]\n      log(:a)\n    else\n      xs.map { |x| log(x) }\n    end\n    xs.sum"
             )).to be_empty
    end

    it "still swaps each in a discarded case/in predicate: the value is matched on" do
      expect(replacements("case xs.each { |x| x }\n    in Array\n      log(:a)\n    end\n    xs.sum")).not_to be_empty
    end

    it "still swaps each inside a node type the discard analysis does not know (conservative)" do
      expect(replacements("(xs.each { |x| x })\n    xs.sum")).not_to be_empty
    end

    it "still swaps min in an else branch body" do
      expect(replacements("if ready?\n      log(:a)\n    else\n      xs.min\n    end")).not_to be_empty
    end

    it "still swaps min in an unless else branch body" do
      expect(replacements("unless ready?\n      log(:a)\n    else\n      xs.min\n    end")).not_to be_empty
    end

    it "still swaps min in an ensure body: only each and map are suppressed in discarded positions" do
      expect(replacements("begin\n      log(:a)\n    ensure\n      xs.min\n    end")).not_to be_empty
    end

    it "still suppresses map in a non-last statement of a predicate's begin body" do
      # used resets the discard depth for the predicate; the non-last
      # statement inside it re-enters a discarded position exactly once.
      expect(replacements(
               "if (begin\n      xs.map { |x| log(x) }\n      true\n    end)\n      log(:a)\n    end\n    xs.sum"
             )).to be_empty
    end

    it "still swaps map in a discarded branch tail on a lazy receiver (#431)" do
      expect(replacements("if ready?\n      xs.lazy.map { |x| x }.force\n    end\n    xs.sum")).not_to be_empty
    end
  end
end
