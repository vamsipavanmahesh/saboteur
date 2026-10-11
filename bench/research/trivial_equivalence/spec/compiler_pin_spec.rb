# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../lib/trivial_equivalence"

RSpec.describe TrivialEquivalence::CompilerPin do
  it "passes the pinned options to the compiler, not the ambient defaults" do
    allow(RubyVM::InstructionSequence).to receive(:compile).and_call_original
    described_class.compile("1\n", "sample.rb")
    expect(RubyVM::InstructionSequence).to have_received(:compile)
      .with("1\n", "sample.rb", "sample.rb", 1, described_class::PINNED_OPTIONS)
  end

  it "refuses to compile on a Ruby series that was not measured" do
    stub_const("RUBY_VERSION", "3.4.0")
    expect { described_class.compile("1\n", "sample.rb") }.to raise_error(described_class::UnpinnedRubyError)
  end
end
