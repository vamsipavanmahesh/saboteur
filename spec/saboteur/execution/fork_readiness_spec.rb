# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Execution::ForkReadiness do
  # Hides one capability for an example, leaving every other respond_to?
  # answer alone.
  def hide_capability(receiver, name)
    allow(receiver).to receive(:respond_to?).and_call_original
    allow(receiver).to receive(:respond_to?).with(name).and_return(false)
  end

  context "on a CRuby with Process.warmup (3.3+)" do
    before { allow(Process).to receive(:warmup) }

    it "warms the heap up and never touches the GC directly" do
      allow(GC).to receive(:start)
      allow(GC).to receive(:compact)
      described_class.prepare_heap
      expect(Process).to have_received(:warmup).once
      expect(GC).not_to have_received(:start)
      expect(GC).not_to have_received(:compact)
    end
  end

  context "without Process.warmup but with GC.compact" do
    before do
      hide_capability(Process, :warmup)
      allow(GC).to receive(:compact)
      allow(GC).to receive(:start)
    end

    it "compacts, letting compact's own full collection do the collecting" do
      described_class.prepare_heap
      expect(GC).to have_received(:compact).once
      # A GC.start next to GC.compact would duplicate a full collection.
      expect(GC).not_to have_received(:start)
    end
  end

  context "with neither capability" do
    before do
      hide_capability(Process, :warmup)
      hide_capability(GC, :compact)
      allow(GC).to receive(:start)
    end

    it "falls back to one full collection" do
      described_class.prepare_heap
      expect(GC).to have_received(:start).with(full_mark: true, immediate_sweep: true).once
    end
  end

  it "returns nil, so callers cannot depend on GC internals" do
    expect(described_class.prepare_heap).to be_nil
  end
end
