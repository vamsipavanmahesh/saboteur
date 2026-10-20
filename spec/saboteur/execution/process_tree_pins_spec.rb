# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Exact behaviour of ProcessTree over a fake process table: who is tracked,
# who counts as live, which signals go to whom, and when a sweep stops. No
# real process is touched; Process.kill is stubbed.
RSpec.describe Saboteur::Execution::ProcessTree, "pins" do
  let(:table_class) { Saboteur::Execution::ProcessTable }
  let(:root) { 4000 }
  let(:marker) { "abcd1234ef01" }
  let(:tree) { described_class.new(root, marker: marker) }
  let(:current) { {} }

  def proc_entry(pid, ppid: 1, pgid: 9999, started: 100, zombie: false, rss: 0)
    table_class::Entry.new(pid: pid, ppid: ppid, pgid: pgid, rss_kb: rss, zombie: zombie, started: started)
  end

  def table(*entries)
    entries.to_h { |entry| [entry.pid, entry] }
  end

  def pids(entries)
    entries.map(&:pid).sort
  end

  before do
    allow(table_class).to receive(:snapshot) { current }
    allow(Process).to receive(:kill)
    allow(Saboteur::Execution::MarkerSweep).to receive(:available?).and_return(true)
    allow(Saboteur::Execution::MarkerSweep).to receive(:marked_pids).and_return([])
    allow(tree).to receive(:sleep)
  end

  describe "#live_members" do
    it "tracks the root by the start time it first shows and nothing without it" do
      expect(tree.live_members(table(proc_entry(7, ppid: root)))).to eq([])
      current.replace(table(proc_entry(root, pgid: root, started: 50)))
      expect(pids(tree.live_members)).to match_array([root])
    end

    it "tracks a root that leads no process group of its own, and its children" do
      current.replace(table(proc_entry(root, pgid: 1, started: 50), proc_entry(11, ppid: root)))
      expect(pids(tree.live_members)).to match_array([root, 11])
    end

    it "follows children by parent link, grandchildren through them, and group members by pgid" do
      current.replace(table(
                        proc_entry(root, pgid: root, started: 50),
                        proc_entry(11, ppid: root),
                        proc_entry(12, ppid: 11),
                        proc_entry(13, ppid: 1, pgid: root),
                        proc_entry(14, ppid: 1, pgid: 5555)
                      ))
      expect(pids(tree.live_members)).to match_array([root, 11, 12, 13])
    end

    it "finds a grandchild listed before its parent in the same snapshot" do
      current.replace(table(proc_entry(12, ppid: 11), proc_entry(11, ppid: root),
                            proc_entry(root, pgid: root, started: 50)))
      expect(pids(tree.live_members)).to match_array([root, 11, 12])
    end

    it "never tracks the calling process, even when it hangs below the root" do
      current.replace(table(proc_entry(root, pgid: root, started: 50),
                            proc_entry(Process.pid, ppid: root, pgid: root)))
      expect(pids(tree.live_members)).to match_array([root])
    end

    it "keeps the root's first start time, so a recycled root pid is not live" do
      current.replace(table(proc_entry(root, pgid: root, started: 50)))
      tree.live_members
      current.replace(table(proc_entry(root, pgid: root, started: 60)))
      expect(tree.live_members).to eq([])
    end

    it "drops members that vanished, were recycled or turned zombie, and keeps the rest" do
      current.replace(table(proc_entry(root, pgid: root, started: 50), proc_entry(21, ppid: root, started: 10),
                            proc_entry(22, ppid: root, started: 10), proc_entry(23, ppid: root, started: 10),
                            proc_entry(24, ppid: root, started: 10)))
      tree.live_members
      current.replace(table(proc_entry(root, pgid: root, started: 50), proc_entry(22, ppid: root, started: 11),
                            proc_entry(23, ppid: root, started: 10, zombie: true),
                            proc_entry(24, ppid: root, started: 10)))
      expect(pids(tree.live_members)).to match_array([root, 24])
    end
  end

  describe "#kill_all" do
    let(:family) do
      table(proc_entry(root, pgid: root, started: 50), proc_entry(31, ppid: root), proc_entry(32, ppid: 31))
    end

    before { current.replace(family) }

    it "stops the members, kills each with KILL and reports the pids it killed" do
      allow(Process).to receive(:kill).with("KILL", anything) { |_name, pid| current.delete(pid) }
      expect(tree.kill_all).to match_array([root, 31, 32])
      [root, 31, 32].each do |pid|
        expect(Process).to have_received(:kill).with("STOP", pid).once
        expect(Process).to have_received(:kill).with("KILL", pid).once
      end
    end

    it "pauses between rounds and stops when nothing is left" do
      allow(table_class).to receive(:snapshot).and_return(family, family, family, {})
      tree.kill_all
      expect(tree).to have_received(:sleep).with(0.01).at_least(:once)
    end

    it "keeps sweeping while an escapee is left even if no member is live" do
      allow(Saboteur::Execution::MarkerSweep).to receive(:marked_pids).and_return([77], [])
      escapee = proc_entry(77, started: 100)
      current.replace(table(escapee))
      expect(tree.kill_all).to eq([77])
      expect(Process).to have_received(:kill).with("KILL", 77)
    end

    it "keeps sweeping while members are live even if no escapee is left" do
      expect(tree.kill_all(rounds: 1)).to match_array([root, 31, 32])
    end

    it "makes at most the given number of rounds" do
      allow(Saboteur::Execution::MarkerSweep).to receive(:marked_pids).and_return([77])
      current.replace(table(proc_entry(77, started: 100)))
      tree.kill_all(rounds: 3)
      expect(Process).to have_received(:kill).with("KILL", 77).exactly(3).times
      expect(tree).to have_received(:sleep).with(0.01).exactly(3).times
    end

    it "lists live pids first, then escapees, each once" do
      allow(Saboteur::Execution::MarkerSweep).to receive(:marked_pids).and_return([77], [])
      current.replace(family.merge(table(proc_entry(77, started: 100))))
      expect(tree.kill_all(rounds: 1)).to eq([root, 31, 32, 77])
    end
  end

  describe "stopping members before the kill" do
    it "stops each member once, and rescans until a round brings nobody new" do
      current.replace(table(proc_entry(root, pgid: root, started: 50), proc_entry(41, ppid: root)))
      live = tree.send(:stop_until_stable)
      expect(pids(live)).to match_array([root, 41])
      expect(Process).to have_received(:kill).with("STOP", root).once
      expect(Process).to have_received(:kill).with("STOP", 41).once
    end

    it "stops a late arrival found on the next scan" do
      current.replace(table(proc_entry(root, pgid: root, started: 50)))
      allow(Process).to receive(:kill).with("STOP", root) do
        current.replace(table(proc_entry(root, pgid: root, started: 50), proc_entry(42, ppid: root)))
      end
      expect(pids(tree.send(:stop_until_stable))).to match_array([root, 42])
      expect(Process).to have_received(:kill).with("STOP", 42).once
    end

    it "gives up after five rounds of new arrivals and returns what is live" do
      serial = 100
      current.replace(table(proc_entry(root, pgid: root, started: 50)))
      allow(Process).to receive(:kill).with("STOP", anything) do
        serial += 1
        current[serial] = proc_entry(serial, ppid: root)
      end
      live = tree.send(:stop_until_stable)
      expect(Process).to have_received(:kill).with("STOP", anything).exactly(5).times
      expect(live.size).to eq(6)
    end
  end

  describe "#marked_escapees" do
    let(:root_entry) { proc_entry(root, pgid: root, started: 50) }

    before do
      current.replace(table(root_entry))
      tree.live_members
    end

    def sweep_finds(*pids)
      allow(Saboteur::Execution::MarkerSweep).to receive(:marked_pids).and_return(pids)
    end

    it "asks the sweep for this run's marker in the tree variable" do
      tree.send(:marked_escapees)
      expect(Saboteur::Execution::MarkerSweep).to have_received(:marked_pids)
        .with(marker, Saboteur::Execution::Supervisor::TREE_ENV)
    end

    it "sweeps nothing without a marker or where the sweep is unavailable" do
      sweep_finds(61)
      current[61] = proc_entry(61)
      expect(described_class.new(root).send(:marked_escapees)).to eq([])
      allow(Saboteur::Execution::MarkerSweep).to receive(:available?).and_return(false)
      expect(tree.send(:marked_escapees)).to eq([])
      expect(Saboteur::Execution::MarkerSweep).not_to have_received(:marked_pids)
    end

    it "returns live, unknown, not-older marked processes only" do
      sweep_finds(61, 62, 63, 64, 65, 66)
      current.merge!(table(proc_entry(61, started: 50), proc_entry(62, zombie: true),
                           proc_entry(64, started: 49), proc_entry(65, started: 51),
                           proc_entry(66, ppid: root, started: 100)))
      tree.live_members # 66 becomes a known member; 63 is in no table
      expect(pids(tree.send(:marked_escapees))).to match_array([61, 65])
    end

    it "does not compare start times when the root itself was never seen" do
      unseen = described_class.new(root + 1, marker: marker)
      allow(Saboteur::Execution::MarkerSweep).to receive(:marked_pids).and_return([71])
      current[71] = proc_entry(71, started: 1)
      expect(pids(unseen.send(:marked_escapees))).to match_array([71])
    end
  end

  describe "#escapee_alive?" do
    let(:seen) { proc_entry(81, started: 100) }

    it "is true only for the same live process" do
      current.replace(table(proc_entry(81, started: 100)))
      expect(tree.send(:escapee_alive?, seen)).to be(true)
      current.replace(table(proc_entry(81, started: 101)))
      expect(tree.send(:escapee_alive?, seen)).to be(false)
      current.replace(table(proc_entry(81, started: 100, zombie: true)))
      expect(tree.send(:escapee_alive?, seen)).to be(false)
      current.replace({})
      expect(tree.send(:escapee_alive?, seen)).to be_falsey
    end
  end

  describe "#signal" do
    it "ignores a process that is gone or not ours, and lets other errors out" do
      allow(Process).to receive(:kill).with("KILL", 1).and_raise(Errno::ESRCH)
      allow(Process).to receive(:kill).with("KILL", 2).and_raise(Errno::EPERM)
      allow(Process).to receive(:kill).with("KILL", 3).and_raise(Errno::EINVAL)
      expect(tree.send(:signal, "KILL", 1)).to be_nil
      expect(tree.send(:signal, "KILL", 2)).to be_nil
      expect { tree.send(:signal, "KILL", 3) }.to raise_error(Errno::EINVAL)
    end
  end

  describe "#kill_all with nothing to kill" do
    it "ends after one look without sleeping or signalling" do
      expect(tree.kill_all).to eq([])
      expect(tree).not_to have_received(:sleep)
      expect(Process).not_to have_received(:kill)
    end
  end

  describe "#usage and #describe_except" do
    before do
      current.replace(table(proc_entry(root, pgid: root, started: 50, rss: 900), proc_entry(91, ppid: root, rss: 500),
                            proc_entry(92, ppid: root, rss: 100)))
    end

    it "counts live members and only the memory above the baseline" do
      expect(tree.usage(200)).to eq([3, 700 + 300])
    end

    it "reads the table it is given, not a fresh snapshot" do
      current.clear
      given = table(proc_entry(root, pgid: root, started: 50, rss: 400), proc_entry(93, ppid: root, rss: 300))
      allow(table_class).to receive(:command).with(93).and_return(nil)
      expect(tree.usage(100, given)).to eq([2, 300 + 200])
      expect(described_class.new(root).describe_except(root, given)).to eq(["93"])
    end

    it "describes every live member but the excluded root, by command when it is known" do
      allow(table_class).to receive(:command).with(91).and_return("ruby -e x")
      allow(table_class).to receive(:command).with(92).and_return(nil)
      expect(tree.describe_except(root)).to eq(["91 (ruby -e x)", "92"])
    end

    it "kills everything, then names the members it left out of the kill list" do
      allow(table_class).to receive(:command).and_return("cmd")
      killed, notes = tree.kill_all_except(root)
      expect(killed.sort).to eq([91, 92])
      expect(notes).to eq(["91 (cmd)", "92 (cmd)"])
    end
  end
end
