# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# A test that suspends Coverage (an in-process Engine#call does) must not
# leave every later test unmeasured: the recorder resumes it after each read.
RSpec.describe Saboteur::Selection::Recorder, "a test that suspends Coverage" do
  let(:recorder) { described_class.new([__FILE__]) }

  before do
    allow(Saboteur::CoverageReads).to receive(:result).and_return({})
    allow(Coverage).to receive(:resume)
    allow(Coverage).to receive(:suspend)
  end

  it "has Coverage resumed after the test finishes" do
    allow(Coverage).to receive(:running?).and_return(false)
    allow(Coverage).to receive(:state).and_return(:suspended)
    recorder.test_started("t1", "s1")
    recorder.test_finished("t1")
    expect(Coverage).to have_received(:resume).twice
  end

  it "resumes the Coverage it suspended itself while reading" do
    allow(Coverage).to receive(:running?).and_return(true)
    allow(Coverage).to receive(:state).and_return(:suspended)
    recorder.test_started("t1", "s1")
    expect(Coverage).to have_received(:suspend).ordered
    expect(Coverage).to have_received(:resume).ordered
  end

  it "does not resume a Coverage that is running" do
    allow(Coverage).to receive(:running?).and_return(false)
    allow(Coverage).to receive(:state).and_return(:running)
    recorder.test_started("t1", "s1")
    expect(Coverage).not_to have_received(:resume)
  end
end
