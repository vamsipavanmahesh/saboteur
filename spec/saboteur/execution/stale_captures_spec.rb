# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Stands in for a load-time registry (RULES = [Limits.method(:min_ok?)]):
# captures survive in long-lived objects, so the spec must hold them too.
module CapturedMethods
  @held = []

  class << self
    def hold(method) = @held << method
    def clear = @held.clear
  end
end

RSpec.describe Saboteur::Execution::StaleCaptures do
  let(:reevaluator) { Saboteur::Execution::Reevaluator.new }

  after { CapturedMethods.clear }

  def setup_target
    subject = subjects_in("class CaptureTarget\n  def min_ok?(amount)\n    amount >= 100\n  end\nend\n").first
    load subject.file
    subject
  end

  it "finds Method objects captured before a re-evaluation, and names the def's site" do
    subject = setup_target
    CapturedMethods.hold(CaptureTarget.new.method(:min_ok?))
    reevaluator.call(subject, subject.source)
    expect(described_class.scan(reevaluator, subject)).to eq(["#{subject.file}:2"])
  end

  it "returns empty when nothing captured the method" do
    subject = setup_target
    reevaluator.call(subject, subject.source)
    expect(described_class.scan(reevaluator, subject)).to eq([])
  end

  it "ignores captures of the current, re-evaluated definition" do
    subject = setup_target
    reevaluator.call(subject, subject.source)
    CaptureTarget.new.method(:min_ok?)
    expect(described_class.scan(reevaluator, subject)).to eq([])
  end

  # The fixture's minimal sorbet-runtime shim: same shape as the real gem
  # (wrapper in a sorbet-runtime path, registry on T::Utils).
  def with_shimmed_subject(id, &block)
    shim = File.expand_path("../../fixtures/projects/sorbet/vendor/sorbet-runtime/lib/sorbet_runtime_shim.rb",
                            __dir__)
    load shim
    subject = subject_named(
      "class #{id}\n  extend T::Sig\n  sig { void }\n  def fee(a)\n    a + 1\n  end\nend\n", "#{id}#fee"
    )
    load subject.file
    block.call(subject)
  end

  it "does not flag the freshly registered def of a re-evaluated wrapper as stale" do
    with_shimmed_subject("FreshWrap") do |subject|
      reevaluator.call(subject, subject.source, prefix: subject.sig_source)
      expect(described_class.scan(reevaluator, subject)).to eq([])
    end
  end

  it "flags the registry's def as stale when the re-eval dropped the sig" do
    with_shimmed_subject("DroppedSig") do |subject|
      reevaluator.call(subject, subject.source)
      expect(described_class.scan(reevaluator, subject)).to eq(["#{subject.file}:4"])
    end
  end

  it "finds captures of singleton methods on the singleton" do
    subject = subjects_in("class SingletonCapture\n  def self.rule(amount)\n    amount >= 100\n  end\nend\n").first
    load subject.file
    CapturedMethods.hold(SingletonCapture.method(:rule))
    reevaluator.call(subject, subject.source)
    expect(described_class.scan(reevaluator, subject)).to eq(["#{subject.file}:2"])
  end
end
