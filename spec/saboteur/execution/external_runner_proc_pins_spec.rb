# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

# Pins for the process reaping helpers of ExternalRunner. Every Process call
# and every sleep is stubbed, so no real child is spawned or signalled and
# the polling cadence is asserted exactly.
RSpec.describe Saboteur::Execution::ExternalRunner, "process pins" do
  let(:root) { File.realpath(Dir.mktmpdir("ext-proc")) }
  let(:runner) { described_class.new(command: "true", root: root) }

  after do
    runner.close
    FileUtils.remove_entry(root)
  end

  describe "#tree_alive?" do
    it "probes the whole process group with signal 0" do
      allow(Process).to receive(:kill).with(0, -123)
      expect(runner.send(:tree_alive?, 123)).to be(true)
      expect(Process).to have_received(:kill).with(0, -123)
    end

    it "is false when the group is gone" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)
      expect(runner.send(:tree_alive?, 123)).to be(false)
    end

    it "is false when the group is not ours to signal" do
      allow(Process).to receive(:kill).and_raise(Errno::EPERM)
      expect(runner.send(:tree_alive?, 123)).to be(false)
    end
  end

  describe "#await_exit" do
    def wait_sequence(*results)
      allow(Process).to receive(:wait2).and_return(*results)
      allow(runner).to receive(:sleep)
    end

    it "returns the exit status once the child is done" do
      status = instance_double(Process::Status, exitstatus: 3)
      wait_sequence([123, status])
      expect(runner.send(:await_exit, 123, 10)).to eq(3)
    end

    it "returns :signal when the child died without an exit status" do
      status = instance_double(Process::Status, exitstatus: nil)
      wait_sequence([123, status])
      expect(runner.send(:await_exit, 123, 10)).to eq(:signal)
    end

    it "polls with WNOHANG every 0.01s until the deadline, then reports :timeout" do
      wait_sequence([nil, nil], [nil, nil])
      allow(runner).to receive(:monotonic).and_return(0.0, 1.0, 2.0)
      expect(runner.send(:await_exit, 123, 1.5)).to eq(:timeout)
      expect(Process).to have_received(:wait2).with(123, Process::WNOHANG).twice
      expect(runner).to have_received(:sleep).with(0.01).once
    end

    it "times out when the clock reaches the deadline exactly" do
      status = instance_double(Process::Status, exitstatus: 0)
      wait_sequence([nil, nil], [123, status])
      allow(runner).to receive(:monotonic).and_return(0.0, 1.5)
      expect(runner.send(:await_exit, 123, 1.5)).to eq(:timeout)
    end

    it "does not time out before the deadline" do
      status = instance_double(Process::Status, exitstatus: 0)
      wait_sequence([nil, nil], [123, status])
      allow(runner).to receive(:monotonic).and_return(0.0, 1.4)
      expect(runner.send(:await_exit, 123, 1.5)).to eq(0)
    end
  end

  describe "#reap_tree" do
    before do
      allow(runner).to receive(:sleep)
      allow(Process).to receive(:kill)
      allow(Process).to receive(:wait2)
    end

    it "does nothing when the tree is already gone" do
      allow(runner).to receive(:tree_alive?).and_return(false)
      runner.send(:reap_tree, 123)
      expect(Process).not_to have_received(:kill)
    end

    it "TERMs the process group, not the single process" do
      allow(runner).to receive(:tree_alive?).and_return(true, false)
      allow(runner).to receive(:monotonic).and_return(0.0, 0.1)
      runner.send(:reap_tree, 123)
      expect(Process).to have_received(:kill).with("TERM", -123)
      expect(Process).not_to have_received(:kill).with("KILL", anything)
    end

    it "waits out a grace of two seconds from now in 0.02s naps before escalating" do
      allow(runner).to receive(:tree_alive?).and_return(true, true, true, true)
      allow(runner).to receive(:monotonic).and_return(100.0, 100.5, 101.5, 102.5, 104.0)
      runner.send(:reap_tree, 123)
      expect(Process).to have_received(:kill).with("TERM", -123)
      expect(runner).to have_received(:sleep).with(0.02).twice
      expect(Process).to have_received(:kill).with("KILL", -123)
    end

    it "stops waiting once the clock reaches the deadline exactly" do
      allow(runner).to receive(:tree_alive?).and_return(true, true, true)
      allow(runner).to receive(:monotonic).and_return(0.0, 2.0, 3.0)
      runner.send(:reap_tree, 123)
      expect(runner).not_to have_received(:sleep).with(0.02)
      expect(Process).to have_received(:kill).with("KILL", -123)
    end

    it "stops waiting as soon as the tree dies, without burning the whole grace" do
      allow(runner).to receive(:tree_alive?).and_return(true, true, false, false)
      allow(runner).to receive(:monotonic).and_return(0.0, 0.1, 0.2, 2.5)
      runner.send(:reap_tree, 123)
      expect(runner).to have_received(:sleep).with(0.02).once
      expect(Process).not_to have_received(:kill).with("KILL", anything)
    end

    it "always reaps the child with wait2" do
      allow(runner).to receive(:tree_alive?).and_return(true, false)
      allow(runner).to receive(:monotonic).and_return(0.0, 0.1)
      runner.send(:reap_tree, 123)
      expect(Process).to have_received(:wait2).with(123)
    end

    it "swallows a race where the group vanishes mid-signal" do
      allow(runner).to receive(:tree_alive?).and_return(true, false)
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)
      expect { runner.send(:reap_tree, 123) }.not_to raise_error
    end
  end
end
