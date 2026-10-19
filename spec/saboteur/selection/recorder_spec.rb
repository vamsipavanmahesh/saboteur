# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Selection::Recorder do
  it "carries the child-loaded sources and the build time into the built map (#353)" do
    map = described_class.new([]).result(build_seconds: 0.1, loaded_files: ["/app/support/helper.rb"])
    expect(map.loaded_files).to eq(["/app/support/helper.rb"])
    expect(map.build_seconds).to eq(0.1)
  end

  it "treats a method whose path cannot be canonicalized as unwanted instead of raising into the program" do
    # Ruby 3.3 refuses to define a method under a NUL-byte file name, so the
    # canonicalizer's ArgumentError is raised by a stub on the real seam.
    recorder = described_class.new([__FILE__])
    allow(Saboteur::Selection::CoverageMap).to receive(:canonical).and_call_original
    allow(Saboteur::Selection::CoverageMap).to receive(:canonical).with(__FILE__).and_raise(ArgumentError)
    calls = recorder.instance_variable_get(:@calls)
    target = Class.new { def zz = 1 }.new
    calls.enable
    result = target.zz
    calls.pause
    expect(result).to eq(1)
    expect(calls.drain).to eq({})
  ensure
    calls&.pause
  end
end
