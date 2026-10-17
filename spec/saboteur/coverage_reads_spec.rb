# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"

# A loaded class that defines a singleton `hash` returning a non-Integer
# (forem's ReactionCategory, #564) breaks Coverage's methods report: the
# C call hashes every method owner and trusts the return type, so any
# Coverage.result read raises TypeError and the run dies as an internal
# error. The guard turns that into a fail-closed refusal that blames the
# app's contract violation. The handler runs no app code: offender names
# come only from the error's own message and backtrace text. (Ruby 3.3
# reproduces the TypeError; the call is stubbed here so the spec holds on
# every ruby.)
RSpec.describe Saboteur::CoverageReads do
  let(:type_error) { TypeError.new("no implicit conversion of Hash into Integer") }

  it "passes a clean Coverage.result through" do
    allow(Coverage).to receive(:result).with(stop: false, clear: false).and_return({ "/a.rb" => {} })
    expect(described_class.result(stop: false, clear: false)).to eq({ "/a.rb" => {} })
  end

  it "names an offender that appears in the error's own backtrace text" do
    type_error.set_backtrace(["/app/models/reaction_category.rb:12:in 'ReactionCategory.hash'",
                              "/x.rb:1:in 'result'"])
    allow(Coverage).to receive(:result).and_raise(type_error)

    expect { described_class.result(stop: false, clear: false) }
      .to raise_error(Saboteur::Error, /ReactionCategory\.hash/)
  end

  it "blames the app's #hash contract violation, not an internal error" do
    allow(Coverage).to receive(:result).and_raise(type_error)

    expect { described_class.result(stop: false, clear: false) }
      .to raise_error(Saboteur::Error, /#hash must return an Integer/)
  end

  it "says the bug is in the loaded application code" do
    allow(Coverage).to receive(:result).and_raise(type_error)

    expect { described_class.result(stop: false, clear: false) }
      .to raise_error(Saboteur::Error, /application/i)
  end

  it "still refuses when the error names no offender" do
    type_error.set_backtrace(["/x.rb:1:in 'result'"])
    allow(Coverage).to receive(:result).and_raise(type_error)

    expect { described_class.result(stop: false, clear: false) }
      .to raise_error(Saboteur::Error, /could not be named/)
  end

  it "re-raises errors that are not TypeError" do
    allow(Coverage).to receive(:result).and_raise(RuntimeError, "boom")

    expect { described_class.result(stop: false, clear: false) }.to raise_error(RuntimeError, "boom")
  end
end
