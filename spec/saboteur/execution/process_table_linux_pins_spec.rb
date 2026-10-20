# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "etc"

RSpec.describe Saboteur::Execution::ProcessTable, "backend pins" do
  let(:linux) { described_class::Linux }
  # After the command name the fields are: state, then 100 + position.
  let(:stat) { "42 (a b)) Z #{(1..60).map { |i| 100 + i }.join(' ')}\n" }

  around do |example|
    saved = linux.instance_variable_get(:@page_kb)
    linux.instance_variable_set(:@page_kb, nil)
    example.run
  ensure
    linux.instance_variable_set(:@page_kb, saved)
  end

  it "reads ppid, pgid, rss, state and start time from their stat positions" do
    allow(File).to receive(:read).with("/proc/42/stat").and_return(stat)
    allow(linux).to receive(:page_kb).and_return(4)
    entry = linux.entry_for(42)
    expect(entry.zombie).to be(true)
    expect([entry.ppid, entry.pgid, entry.rss_kb, entry.started]).to eql([101, 102, 121 * 4, 119])
  end

  it "is nil when the process vanished" do
    allow(File).to receive(:read).with("/proc/9/stat").and_raise(Errno::ENOENT)
    expect(linux.entry_for(9)).to be_nil
  end

  it "keeps only all-digit names and skips vanished processes" do
    allow(Dir).to receive(:children).with("/proc").and_return(%w[7 1x x5 abc 9])
    allow(File).to receive(:read).and_return(stat)
    allow(File).to receive(:read).with("/proc/9/stat").and_raise(Errno::ENOENT)
    allow(linux).to receive(:page_kb).and_return(4)
    expect(linux.snapshot.keys).to eq([7])
  end

  it "asks the system page size once and falls back to 4 KB when it fails" do
    allow(Etc).to receive(:sysconf).with(Etc::SC_PAGESIZE).and_return(16_384)
    expect([linux.page_kb, linux.page_kb]).to eq([16, 16])
    expect(Etc).to have_received(:sysconf).once
    linux.instance_variable_set(:@page_kb, nil)
    allow(Etc).to receive(:sysconf).with(Etc::SC_PAGESIZE).and_raise(ArgumentError)
    expect(linux.page_kb).to eq(4)
  end

  describe "backend choice" do
    around do |example|
      saved = described_class.instance_variable_get(:@backend)
      example.run
    ensure
      described_class.instance_variable_set(:@backend, saved)
    end

    it "uses the first available backend and remembers it" do
      first = Module.new
      last = Module.new
      described_class.instance_variable_set(:@backend, nil)
      allow(described_class).to receive(:backends).and_return([first, last], [last])
      expect(described_class.backend).to equal(first)
      expect(described_class.backend).to equal(first)
    end

    it "does not hide a failure of the ps backend" do
      allow(described_class).to receive(:backend).and_return(described_class::Ps)
      allow(described_class::Ps).to receive(:snapshot).and_raise(Errno::EPERM)
      expect { described_class.snapshot }.to raise_error(Errno::EPERM)
      expect(described_class::Ps).to have_received(:snapshot).once
    end
  end
end
