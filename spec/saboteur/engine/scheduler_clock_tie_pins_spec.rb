# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Pins the budget deadline at an exact clock tie: a clock reading equal to the
# deadline is already spent, so no further mutant starts.
RSpec.describe Saboteur::Engine::Scheduler, "deadline tie" do
  let(:scheduler) do
    described_class.new(config: Saboteur::Config.new({}), runner: nil, map: nil, deadline: 100.0, reevaluator: nil,
                        diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new))
  end
  let(:candidates) { [[Struct.new(:coarse).new(false), "text"]] }

  def at_clock(value)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(value)
  end

  it "starts no mutant when the clock equals the deadline" do
    at_clock(100.0)
    ran = []
    expect(scheduler.send(:run_candidates, candidates) { |*args| ran << args }).to eq([])
    expect(ran).to be_empty
  end

  it "still runs a mutant one tick before the deadline" do
    at_clock(99.999)
    expect(scheduler.send(:run_candidates, candidates) { |_mutation, text| text }).to eq(["text"])
  end

  it "reports the budget spent at the exact deadline and not before" do
    at_clock(100.0)
    expect(scheduler.send(:budget_spent?)).to be(true)
    at_clock(99.999)
    expect(scheduler.send(:budget_spent?)).to be(false)
  end
end
