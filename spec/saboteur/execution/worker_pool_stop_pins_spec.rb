# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Unit pins for WorkerPool's start, stop, abandon and reap paths, driven by
# stand-in workers and stubbed process calls: nothing is forked or signalled.
RSpec.describe Saboteur::Execution::WorkerPool, "stop pins" do
  let(:pool) { described_class.new(jobs: 2) }
  let(:commands) { instance_double(IO, closed?: true) }
  let(:results) { instance_double(IO, closed?: true) }
  let(:worker) { described_class::Worker.new(0, 4242, commands, results, nil, 0) }
  let(:exit_status) { instance_double(Process::Status) }
  let(:tree) { instance_double(Saboteur::Execution::ProcessTree, kill_all: []) }

  before do
    allow(pool).to receive_messages(sleep: nil, sweep: nil, drain: nil)
    allow(Process).to receive(:wait2).and_return([4242, exit_status])
  end

  describe "#reaped?" do
    it "trusts a recorded status without asking the kernel" do
      allow(Process).to receive(:waitpid2)
      worker.status = exit_status
      expect(pool.send(:reaped?, worker)).to be(true)
      expect(Process).not_to have_received(:waitpid2)
    end

    it "records the status of a worker that has exited, and says false for one that has not" do
      allow(Process).to receive(:waitpid2).with(4242, Process::WNOHANG).and_return([4242, exit_status], nil)
      expect(pool.send(:reaped?, worker)).to be(true)
      expect(worker.status).to be(exit_status)
      other = described_class::Worker.new(1, 4243, nil, nil, nil, 0)
      allow(Process).to receive(:waitpid2).with(4243, Process::WNOHANG).and_return(nil)
      expect(pool.send(:reaped?, other)).to be(false)
      expect(other.status).to be_nil
    end

    it "counts a worker someone else already reaped as gone" do
      allow(Process).to receive(:waitpid2).and_raise(Errno::ECHILD)
      expect(pool.send(:reaped?, worker)).to be(true)
    end
  end

  describe "#stop" do
    before { allow(Saboteur::Execution::Supervisor).to receive(:live).and_return({ 4242 => tree }) }

    it "closes only the pipes that are still open" do
      allow(commands).to receive(:closed?).and_return(false)
      allow(results).to receive(:closed?).and_return(false)
      allow(commands).to receive(:close)
      allow(results).to receive(:close)
      allow(pool).to receive(:reaped?).and_return(true)
      pool.send(:stop, worker)
      expect(commands).to have_received(:close).once
      expect(results).to have_received(:close).once
    end

    it "never closes a pipe that is already closed" do
      allow(commands).to receive(:close).and_raise("closed twice")
      allow(results).to receive(:close).and_raise("closed twice")
      allow(pool).to receive(:reaped?).and_return(true)
      expect { pool.send(:stop, worker) }.not_to raise_error
    end

    it "sweeps the tree it removed from the live registry" do
      allow(pool).to receive(:reaped?).and_return(true)
      pool.send(:stop, worker)
      expect(pool).to have_received(:sweep).with(tree, worker)
      expect(Saboteur::Execution::Supervisor.live).to be_empty
    end

    it "waits for the worker to exit up to five seconds, in 0.01 second naps, then gives up" do
      allow(pool).to receive(:reaped?).and_return(false)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC)
                                               .and_return(100.0, 104.9, 105.0, 105.1, 200.0)
      pool.send(:stop, worker)
      expect(pool).to have_received(:sleep).with(0.01).twice
    end

    it "does not nap for a worker that has already exited" do
      allow(pool).to receive(:reaped?).and_return(true)
      pool.send(:stop, worker)
      expect(pool).not_to have_received(:sleep)
      expect(Process).not_to have_received(:wait2)
    end

    it "waits for a worker still running past the grace and keeps the exit status it gets" do
      allow(pool).to receive(:reaped?).and_return(false)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0.0, 9.0)
      pool.send(:stop, worker)
      expect(Process).to have_received(:wait2).with(4242)
      expect(worker.status).to be(exit_status)
    end

    it "keeps a status it already has" do
      other_status = instance_double(Process::Status)
      worker.status = other_status
      allow(pool).to receive(:reaped?).and_return(false)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0.0, 9.0)
      pool.send(:stop, worker)
      expect(worker.status).to be(other_status)
    end

    it "carries on when the worker was reaped behind its back" do
      allow(pool).to receive(:reaped?).and_return(false)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0.0, 9.0)
      allow(Process).to receive(:wait2).and_raise(Errno::ECHILD)
      expect { pool.send(:stop, worker) }.not_to raise_error
    end
  end

  describe "#abandon_all" do
    before { allow(Saboteur::Execution::Supervisor).to receive(:live).and_return({ 4242 => tree }) }

    it "kills the tree, reaps the worker, and forgets it" do
      allow(commands).to receive(:closed?).and_return(false)
      allow(commands).to receive(:close)
      allow(results).to receive(:closed?).and_return(false)
      allow(results).to receive(:close)
      allow(pool).to receive(:reaped?).and_return(false)
      workers = [worker]
      pool.send(:abandon_all, workers)
      expect(tree).to have_received(:kill_all)
      expect(commands).to have_received(:close)
      expect(results).to have_received(:close)
      expect(Process).to have_received(:wait2).with(4242)
      expect(worker.status).to be(exit_status)
      expect(workers).to be_empty
    end

    it "copes with a worker that has no registered tree, and leaves closed pipes and reaped workers be" do
      allow(Saboteur::Execution::Supervisor).to receive(:live).and_return({})
      allow(commands).to receive(:close).and_raise("closed twice")
      allow(results).to receive(:close).and_raise("closed twice")
      allow(pool).to receive(:reaped?).and_return(true)
      workers = [worker]
      expect { pool.send(:abandon_all, workers) }.not_to raise_error
      expect(Process).not_to have_received(:wait2)
      expect(workers).to be_empty
    end

    it "keeps a status it already has" do
      kept = instance_double(Process::Status)
      worker.status = kept
      allow(pool).to receive(:reaped?).and_return(false)
      pool.send(:abandon_all, [worker])
      expect(Process).not_to have_received(:wait2)
      expect(worker.status).to be(kept)
    end

    it "forgets a worker whose process was already reaped elsewhere" do
      allow(pool).to receive(:reaped?).and_return(false)
      allow(Process).to receive(:wait2).and_raise(Errno::ECHILD)
      workers = [worker]
      expect { pool.send(:abandon_all, workers) }.not_to raise_error
      expect(workers).to be_empty
    end
  end

  describe "#sweep" do
    it "does not need a tree, and keeps the first error it hit" do
      allow(pool).to receive(:sweep).and_call_original
      allow(pool).to receive(:kill_hard)
      first = Errno::EIO.new("first")
      allow(tree).to receive(:kill_all).and_raise(first)
      pool.send(:sweep, nil, worker)
      expect(pool.instance_variable_get(:@sweep_error)).to be_nil
      pool.send(:sweep, tree, worker)
      allow(tree).to receive(:kill_all).and_raise(Errno::EIO.new("second"))
      pool.send(:sweep, tree, worker)
      expect(pool.instance_variable_get(:@sweep_error)).to be(first)
    end
  end

  describe "#distribute" do
    it "forgets an earlier sweep error and raises none for a clean run" do
      pool.instance_variable_set(:@sweep_error, Errno::EIO.new("old"))
      expect(pool.send(:distribute, [], [])).to eq([])
    end

    it "starts one worker per item up to the job count" do
      allow(pool).to receive_messages(start: worker, assign: nil, stop: nil)
      allow(pool).to receive(:collect) { |workers| workers.clear } # rubocop:disable Style/SymbolProc
      pool.send(:distribute, [1], [0])
      expect(pool).to have_received(:start).once
    end

    it "lets the original error out when the run failed before any worker existed" do
      expect { pool.send(:distribute, nil, []) }.to raise_error(NoMethodError, /size/)
    end
  end

  describe "#start" do
    it "closes the parent's copies of the child's pipe ends, takes the child into its own group and registers it" do
      commands_read = instance_double(IO, close: nil)
      results_write = instance_double(IO, close: nil)
      allow(IO).to receive(:pipe).and_return([commands_read, :commands_write], [:results_read, results_write])
      allow(pool).to receive_messages(fork: 4242, own_group: nil)
      allow(Saboteur::Execution::Supervisor).to receive(:live).and_return(live = {})
      started = pool.send(:start, 2, [], [])
      expect(commands_read).to have_received(:close)
      expect(results_write).to have_received(:close)
      expect(pool).to have_received(:own_group).with(4242)
      expect(live.keys).to eq([4242])
      expect([started.number, started.pid, started.commands,
              started.results]).to eq([2, 4242, :commands_write, :results_read])
    end
  end
end
