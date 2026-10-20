# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Execution::PeakMemory, "exact parsing" do
  it "reads the high-water mark in MB, rounded to one decimal" do
    expect(described_class.rss_mb("Name: x\nVmHWM:\t10485760 kB\n")).to eql(10_240.0)
    expect(described_class.rss_mb("VmHWM:2048 kB")).to eql(2.0)
    expect(described_class.rss_mb("VmHWM: 1500 kB")).to eql(1.5)
  end

  it "ignores lookalike lines and missing numbers" do
    expect(described_class.rss_mb("XVmHWM: 2048 kB")).to be_nil
    expect(described_class.rss_mb("VmHWM: kB")).to be_nil
  end

  it "is nil for an unreadable status file" do
    expect(described_class.peak_mb("/nonexistent/saboteur/status")).to be_nil
  end
end

RSpec.describe Saboteur::Execution::FiddleLoader, "require scope" do
  before { allow(described_class).to receive(:require).and_call_original }

  it "loads fiddle/import only when asked" do
    described_class.require_fiddle!
    expect(described_class).not_to have_received(:require).with("fiddle/import")
    described_class.require_fiddle!(with_import: true)
    expect(described_class).to have_received(:require).with("fiddle/import")
  end
end
