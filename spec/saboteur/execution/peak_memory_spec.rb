# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Execution::PeakMemory do
  it "reads the peak RSS from proc status content (#202)" do
    status = "Name:\tsaboteur\nVmHWM:\t   12345 kB\nVmRSS:\t   10000 kB\n"
    expect(described_class.rss_mb(status)).to eq(12.1)
  end

  it "is nil when the content has no VmHWM line" do
    expect(described_class.rss_mb("Name:\tsaboteur\nVmRSS:\t   10000 kB\n")).to be_nil
  end

  it "reads this process's own peak by default" do
    skip "procfs only" unless File.exist?("/proc/self/status")

    expect(described_class.peak_mb).to be > 0
  end
end
