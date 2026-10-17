# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# #389: the marker sweep matches pids, but a pid is not an identity - the
# escapee can exit between the sweep's snapshot and the KILL, and the kernel
# can hand the pid to someone else. The tree must re-verify identity (start
# time) before signalling an escapee, and must not touch a marked process
# that started before the run's root: it inherited the marker through an
# exec chain the run did not spawn.
RSpec.describe Saboteur::Execution::ProcessTree do
  let(:entry_class) { Saboteur::Execution::ProcessTable::Entry }

  let(:marker) { "abcd1234ef01" }
  let(:root) { 4000 }
  let(:tree) { described_class.new(root, marker:) }
  let(:root_entry) { entry_class.new(pid: root, ppid: 1, pgid: root, rss_kb: 0, zombie: true, started: 50) }

  def escapee(started, pid: 4242)
    entry_class.new(pid: pid, ppid: 1, pgid: 9999, rss_kb: 0, zombie: false, started: started)
  end

  before do
    allow(Process).to receive(:kill)
    allow(Saboteur::Execution::MarkerSweep).to receive(:available?).and_return(true)
  end

  it "kills an escapee whose identity is stable between sweep and kill" do
    sweep = { root => root_entry, 4242 => escapee(100) }
    allow(Saboteur::Execution::ProcessTable).to receive(:snapshot).and_return(
      { root => root_entry }, sweep, sweep, sweep
    )
    allow(Saboteur::Execution::MarkerSweep).to receive(:marked_pids).and_return([4242], [])

    expect(tree.kill_all).to include(4242)
    expect(Process).to have_received(:kill).with("KILL", 4242)
  end

  it "does not kill an escapee whose pid was recycled between sweep and kill (#389)" do
    sweep = { root => root_entry, 4242 => escapee(100) }
    recycled = { root => root_entry, 4242 => escapee(999) }
    allow(Saboteur::Execution::ProcessTable).to receive(:snapshot).and_return(
      { root => root_entry }, sweep, recycled, recycled
    )
    allow(Saboteur::Execution::MarkerSweep).to receive(:marked_pids).and_return([4242], [])

    expect(tree.kill_all).not_to include(4242)
    expect(Process).not_to have_received(:kill).with("KILL", 4242)
  end

  it "does not kill a marked process that started before the run's root (#389)" do
    sweep = { root => root_entry, 4242 => escapee(40) }
    allow(Saboteur::Execution::ProcessTable).to receive(:snapshot).and_return(
      { root => root_entry }, sweep, sweep, sweep
    )
    allow(Saboteur::Execution::MarkerSweep).to receive(:marked_pids).and_return([4242], [])

    expect(tree.kill_all).not_to include(4242)
    expect(Process).not_to have_received(:kill).with("KILL", 4242)
  end
end
