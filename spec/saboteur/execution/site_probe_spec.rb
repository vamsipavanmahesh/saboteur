# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

# #1290: the child records whether the mutated expression produced a value
# different from the original one, only where evaluating both is free of
# side effects. Everything else stays unprobed (nil).
RSpec.describe Saboteur::Execution::SiteProbe do
  let(:fee_source) do
    <<~RUBY
      class Fee
        def self.for(amount) = amount < 1_000 ? 10 : amount / 100
        def self.exact(amount) = amount * 3
        def self.call_it(amount) = amount.abs
      end
    RUBY
  end

  def candidates(source = fee_source)
    Dir.mktmpdir do |dir|
      file = File.join(dir, "fee.rb")
      File.write(file, source)
      parsed = Saboteur::SubjectFinder.new.call(file)
      parsed.subjects.flat_map do |subject|
        Saboteur::MutationSource::Builtin.new(arid: []).mutations_for(subject).reject(&:coarse).map do |mutation|
          [subject, mutation, subject.apply(mutation.edits)]
        end
      end
    end
  end

  def find(subject_id, operator, replacement)
    candidates.find do |subject, mutation, _text|
      subject.id == subject_id && mutation.operator == operator && mutation.edits.first.replacement == replacement
    end
  end

  def probe_for(subject_id, operator, replacement)
    subject, mutation, text = find(subject_id, operator, replacement)
    described_class.text(subject, mutation, text)
  end

  it "wraps the whole comparison when only its operator is edited" do
    expect(probe_for("Fee.for", "comparison", "<=")).to include(
      "(::Saboteur::Execution::SiteProbe.observe((amount <= 1_000), [amount]) { amount < 1_000 })"
    )
  end

  it "climbs from an edited literal to the enclosing pure expression" do
    expect(probe_for("Fee.for", "literal_number", "1001")).to include(
      "(::Saboteur::Execution::SiteProbe.observe((amount < 1001), [amount]) { amount < 1_000 })"
    )
  end

  it "probes arithmetic" do
    expect(probe_for("Fee.exact", "arithmetic", "/")).to include(
      "(::Saboteur::Execution::SiteProbe.observe((amount / 3), [amount]) { amount * 3 })"
    )
  end

  it "does not probe a bare literal whose enclosing expression calls a method" do
    source = "class Fee\n  def self.for(amount) = helper(amount) + 1\nend\n"
    subject, mutation, text = candidates(source).find { |_s, m, _t| m.edits.first.replacement == "2" }

    expect(described_class.text(subject, mutation, text)).to be_nil
  end

  it "does not probe a bare edited literal, whose value differs by construction" do
    expect(probe_for("Fee.for", "literal_number", "11")).to be_nil
  end

  it "wraps a whole-condition replacement as the original condition against the constant" do
    expect(probe_for("Fee.for", "condition_true", "true")).to include("observe((true), [amount]) { amount < 1_000 }")
  end

  it "returns nil when the mutated text is not the edits applied to the source" do
    subject, mutation, = find("Fee.for", "comparison", "<=")

    expect(described_class.text(subject, mutation, "something else")).to be_nil
  end

  describe ".observe" do
    before { described_class.reset }

    it "returns the mutated value and records that the values differed" do
      expect(described_class.observe(2, [1]) { 1 }).to eq(2)
      expect(described_class.differed).to be(true)
    end

    it "records false when every observed pair was equal" do
      described_class.observe(true, [1]) { true }
      described_class.observe(false, [2]) { false }

      expect(described_class.differed).to be(false)
    end

    it "stays true once any pair differed" do
      described_class.observe(1, [1]) { 1 }
      described_class.observe(2, [1]) { 1 }
      described_class.observe(3, [3]) { 3 }

      expect(described_class.differed).to be(true)
    end

    it "is nil when the site never ran" do
      expect(described_class.differed).to be_nil
    end

    it "is nil, not a verdict, when the original raises" do
      described_class.observe(1, [0]) { raise ZeroDivisionError }

      expect(described_class.differed).to be_nil
    end

    it "never runs the original when an operand is not a core immutable" do
      meter = Object.new
      calls = 0
      def meter.>(_other) = raise("the stubbed operator must not run twice")

      result = described_class.observe(true, [meter]) { calls += 1 }

      expect(result).to be(true)
      expect(calls).to eq(0)
      expect(described_class.differed).to be_nil
    end

    it "treats frozen strings as immutable and unfrozen ones as not" do
      described_class.observe("a", ["a"]) { "b" }
      expect(described_class.differed).to be(true)
      described_class.reset
      described_class.observe("a", [+"a"]) { "b" }
      expect(described_class.differed).to be_nil
    end
  end

  it "reports no difference for the Fee.for boundary under tests at 500 and 1_000_000" do
    subject, mutation, text = find("Fee.for", "comparison", "<=")
    probed = described_class.text(subject, mutation, text)
    described_class.reset
    klass = Class.new
    klass.class_eval(probed.sub("def self.for", "def probed"))
    klass.new.probed(500)
    klass.new.probed(1_000_000)

    expect(described_class.differed).to be(false)

    klass.new.probed(1_000)

    expect(described_class.differed).to be(true)
  end
end
