# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# LoadCoverage reads the boot snapshot through CoverageReads (#564), so a
# loaded class whose #hash is not an Integer reaches the user as a saboteur
# refusal instead of a raw TypeError crash.
RSpec.describe Saboteur::Engine::LoadCoverage, "coverage reads (#564)" do
  before { allow(Coverage).to receive(:state).and_return(:suspended) }

  it "reads the snapshot without stopping or clearing Coverage, through CoverageReads" do
    allow(Saboteur::CoverageReads).to receive(:result).and_return({})
    described_class.capture([])
    expect(Saboteur::CoverageReads).to have_received(:result).with(stop: false, clear: false).once
  end

  it "turns a TypeError from the Coverage read into the saboteur refusal with the diagnostic" do
    allow(Coverage).to receive(:result).and_raise(TypeError, "can't convert Foo to Integer (Foo#hash gives String)")
    expect { described_class.capture([]) }
      .to raise_error(Saboteur::Error, /Coverage\.result raised TypeError \(can't convert Foo to Integer/)
  end
end
