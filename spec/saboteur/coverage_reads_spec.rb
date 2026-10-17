# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"

# A loaded class that defines a singleton `hash` returning a non-Integer
# (forem's ReactionCategory, #564) breaks Coverage's methods report: the
# C call hashes every method owner and trusts the return type, so any
# Coverage.result read raises TypeError and the run dies as an internal
# error. The guard turns that into a clear refusal naming the offender.
# (Ruby 3.3 reproduces the TypeError; the call is stubbed here so the spec
# holds on every ruby.)
RSpec.describe Saboteur::CoverageReads do
  let(:type_error) { TypeError.new("no implicit conversion of Hash into Integer") }

  it "passes a clean Coverage.result through" do
    allow(Coverage).to receive(:result).with(stop: false, clear: false).and_return({ "/a.rb" => {} })
    expect(described_class.result(stop: false, clear: false)).to eq({ "/a.rb" => {} })
  end

  it "refuses with a diagnostic naming the class whose singleton hash breaks the contract" do
    stub_const("ReactionCategory", Class.new do
      def self.hash
        {}
      end
    end)
    allow(Coverage).to receive(:result).and_raise(type_error)

    expect { described_class.result(stop: false, clear: false) }
      .to raise_error(Saboteur::Error, /no implicit conversion of Hash into Integer.*ReactionCategory/m)
  end

  it "points at the singleton `hash` contract when it refuses" do
    stub_const("ReactionCategory", Class.new do
      def self.hash
        {}
      end
    end)
    allow(Coverage).to receive(:result).and_raise(type_error)

    expect { described_class.result(stop: false, clear: false) }
      .to raise_error(Saboteur::Error, /singleton `hash`/)
  end

  it "still refuses, without naming, when no override is found" do
    # A suite in progress can hold unrelated singleton `hash` overrides.
    allow(described_class).to receive(:hash_contract_violators).and_return([])
    allow(Coverage).to receive(:result).and_raise(type_error)

    expect { described_class.result(stop: false, clear: false) }
      .to raise_error(Saboteur::Error, /no singleton `hash` override found/)
  end

  it "finds singleton `hash` overrides without flagging ordinary classes" do
    stub_const("ReactionCategory", Class.new do
      def self.hash
        {}
      end
    end)

    expect(described_class.hash_contract_violators).to include("ReactionCategory.hash")
    expect(described_class.hash_contract_violators).not_to include("String.hash")
  end

  it "re-raises errors that are not TypeError" do
    allow(Coverage).to receive(:result).and_raise(RuntimeError, "boom")

    expect { described_class.result(stop: false, clear: false) }.to raise_error(RuntimeError, "boom")
  end
end
