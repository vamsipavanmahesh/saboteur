# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"

# A loaded class whose `hash` does not return an Integer (forem's
# ReactionCategory, #564) breaks Coverage's methods report: the C call
# hashes every method owner and trusts the return type, so any
# Coverage.result read raises TypeError and the run dies as an internal
# error. The guard turns that into a fail-closed refusal that blames the
# app's contract violation without accusing any class the error did not
# name. (Ruby 3.3 reproduces the TypeError inside Coverage.result; the
# read is stubbed here with a really-raised TypeError so the spec holds
# on every ruby.)
RSpec.describe Saboteur::CoverageReads do
  # A TypeError Ruby really raised, backtrace and all - hashing a class
  # whose singleton `hash` returns a Hash.
  def real_type_error
    bad_owner = Class.new do
      def self.hash
        {}
      end
    end
    {}.tap { |hash| hash[bad_owner] = 1 }
    raise "unreachable"
  rescue TypeError => e
    e
  end

  it "passes a clean Coverage.result through" do
    allow(Coverage).to receive(:result).with(stop: false, clear: false).and_return({ "/a.rb" => {} })
    expect(described_class.result(stop: false, clear: false)).to eq({ "/a.rb" => {} })
  end

  it "refuses with the #hash contract violation, blaming the application's code" do
    allow(Coverage).to receive(:result).and_raise(real_type_error)

    expect { described_class.result(stop: false, clear: false) }
      .to raise_error(Saboteur::Error, /#hash does not return an Integer.*application's code/m)
  end

  it "accuses no class the error did not name" do
    allow(Coverage).to receive(:result).and_raise(real_type_error)

    expect { described_class.result(stop: false, clear: false) }
      .to raise_error(Saboteur::Error) { |error| expect(error.message).not_to match(/Offending|ReactionCategory/) }
  end

  it "re-raises errors that are not TypeError" do
    allow(Coverage).to receive(:result).and_raise(RuntimeError, "boom")

    expect { described_class.result(stop: false, clear: false) }.to raise_error(RuntimeError, "boom")
  end
end
