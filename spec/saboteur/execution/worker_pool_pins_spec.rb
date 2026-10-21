# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Unit pins for WorkerPool's bookkeeping, driven through fake workers and pipes
# so no process is forked. The forking paths live in worker_pool_spec.rb.
RSpec.describe Saboteur::Execution::WorkerPool, "pins" do
  let(:pool) { described_class.new(jobs: 2, drain_timeout: 30) }
  let(:worker_class) { described_class::Worker }
  let(:worker) { worker_class.new(3, 999_999, nil, nil, 5, 0) }

  def clock_at(value)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(value)
  end

  describe "#give_up" do
    it "raises on the third failure and on every one after, and not before" do
      2.times { expect { pool.send(:give_up, "boom") }.not_to raise_error }
      expect { pool.send(:give_up, "boom") }.to raise_error(Saboteur::Error, "workers keep failing to start: boom")
      expect { pool.send(:give_up, "boom") }.to raise_error(Saboteur::Error, /keep failing/)
    end
  end

  describe "#map" do
    it "runs the heaviest items first and ties in item order, but returns results in item order" do
      seen = []
      pool = described_class.new(jobs: 1)
      results = pool.map(%w[a b c d], weights: [1, 3, 1, 3]) { |item| (seen << item) && item.upcase }
      expect(seen).to eq(%w[b d a c])
      ties = Array.new(12) { |n| n }
      order = []
      pool.map(ties, weights: Array.new(12, 2)) { |n| order << n }
      expect(order).to eq(ties)
      expect(results).to eq(%w[A B C D])
    end

    it "runs inline for a single job and for none" do
      expect(described_class.new(jobs: 1).map([1, 2]) { |n| n * 2 }).to eq([2, 4])
      expect(described_class.new(jobs: 0).map([1, 2]) { |n| n * 3 }).to eq([3, 6])
    end
  end

  describe "#halt!" do
    it "sets the drain deadline once, from the first halt that drains" do
      clock_at(10.0)
      pool.halt!(drain: false)
      expect(pool.instance_variable_get(:@drain_deadline)).to be_nil
      pool.halt!
      expect(pool.instance_variable_get(:@drain_deadline)).to eq(40.0)
      clock_at(20.0)
      pool.halt!
      expect(pool.instance_variable_get(:@drain_deadline)).to eq(40.0)
    end
  end

  describe "#collect" do
    let(:reader) { IO.pipe.first }

    before do
      worker.results = reader
      allow(IO).to receive(:select).and_return(nil)
      allow(pool).to receive(:alive?).and_return(true)
    end

    after { reader.close }

    def collect
      pool.send(:collect, [worker], [], [], [])
    end

    it "waits one second for results when the pool is not draining" do
      collect
      expect(IO).to have_received(:select).with([reader], nil, nil, 1)
    end

    it "waits for the drain deadline when it is closer than a second" do
      clock_at(100.0)
      pool.instance_variable_set(:@drain_deadline, 100.5)
      collect
      expect(IO).to have_received(:select).with([reader], nil, nil, 0.5)
    end

    it "keeps the one second wait when the deadline is further away" do
      clock_at(100.0)
      pool.instance_variable_set(:@drain_deadline, 160.0)
      collect
      expect(IO).to have_received(:select).with([reader], nil, nil, 1)
    end

    it "abandons every worker once the deadline has been reached, and not a moment before" do
      allow(pool).to receive(:abandon_all)
      clock_at(100.0)
      pool.instance_variable_set(:@drain_deadline, 100.0)
      collect
      expect(pool).to have_received(:abandon_all).with([worker])
      expect(IO).not_to have_received(:select)
    end

    it "ignores a ready pipe that belongs to no worker" do
      allow(IO).to receive(:select).and_return([[IO.pipe.first]])
      allow(pool).to receive(:receive)
      collect
      expect(pool).not_to have_received(:receive)
    end
  end

  describe "#take" do
    let(:results) { {} }

    it "files a peak report under the worker it names, or else the worker's number" do
      pool.send(:take, worker, '{"peak_rss_mb":5,"worker":7}', results)
      pool.send(:take, worker, '{"peak_rss_mb":9}', results)
      expect(pool.worker_peaks).to eq(7 => 5, 3 => 9)
      expect(worker.peak_rss_mb).to eq(9)
      expect(results).to be_empty
      expect([worker.current, worker.done]).to eq([5, 0])
    end

    it "keeps a fatal line as the worker's last words, leaving its item in flight" do
      pool.send(:take, worker, '{"fatal":"out of memory"}', results)
      expect(worker.last_words).to eq("out of memory")
      expect([results, worker.current, worker.done]).to eq([{}, 5, 0])
    end

    it "stores a result against the worker's item and frees the worker" do
      pool.send(:take, worker, '{"x":1}', results)
      pool.send(:take, worker, '{"x":2}', results)
      expect(results).to eq(5 => { "x" => 1 })
      expect([worker.current, worker.done]).to eq([nil, 1])
    end

    it "counts one finished item per result" do
      worker.done = 4
      pool.send(:take, worker, '{"x":1}', results)
      expect(worker.done).to eq(5)
    end
  end

  describe "#take_and_report" do
    let(:seen) { [] }
    let(:pool) { described_class.new(jobs: 2, on_result: ->(index, row) { seen << [index, row] }) }

    it "reports the item and its row once a result lands" do
      pool.send(:take_and_report, worker, '{"x":1}', results = {})
      expect(seen).to eq([[5, { "x" => 1 }]])
      expect(results).to eq(5 => { "x" => 1 })
    end

    it "reports nothing for a line that carries no result" do
      pool.send(:take_and_report, worker, '{"peak_rss_mb":5}', {})
      worker.current = nil
      pool.send(:take_and_report, worker, '{"x":1}', {})
      expect(seen).to be_empty
    end
  end

  describe "#parse and #how" do
    it "turns an unreadable result line into an error row" do
      expect(pool.send(:parse,
                       "{nope")).to include("error" => a_string_matching(/\Aunreadable result from worker: .+/))
    end

    it "describes how a worker ended" do
      signaled = instance_double(Process::Status, signaled?: true, termsig: 9)
      exited = instance_double(Process::Status, signaled?: false, exitstatus: 3)
      expect([nil, signaled, exited].map { |status| pool.send(:how, status) })
        .to eq(["", " (signal KILL)", " (exit 3)"])
    end
  end

  describe "#receive" do
    it "hands a dead worker's pipe to replace, and returns what it returns" do
      reader, writer = IO.pipe
      writer.close
      worker.results = reader
      allow(pool).to receive(:replace).and_return(:replaced)
      expect(pool.send(:receive, worker, [worker], [], {}, [])).to eq(:replaced)
    end

    it "leaves a healthy worker alone" do
      reader, writer = IO.pipe
      writer.puts('{"x":1}')
      worker.results = reader
      allow(pool).to receive(:replace)
      allow(pool).to receive(:assign)
      allow(pool).to receive(:retire)
      pool.send(:receive, worker, [worker], [], {}, [])
      expect(pool).not_to have_received(:replace)
    end
  end

  describe "#replace" do
    let(:seen) { [] }
    let(:pool) { described_class.new(jobs: 2, on_result: ->(index, row) { seen << [index, row] }) }
    let(:fresh) { worker_class.new(3, 1, nil, nil, nil, 0) }

    before do
      allow(pool).to receive_messages(drain: nil, retire: nil, start: fresh, assign: nil)
      worker.last_words = "oom"
    end

    it "drains the dead worker, then reports its item as failed with the reason" do
      worker.done = 1
      results = {}
      pool.send(:replace, worker, [], [], results, [])
      expect(pool).to have_received(:drain).with(worker, results)
      expect(results[5]).to eq("error" => "oom, running this item")
      expect(seen).to eq([[5, results[5]]])
    end

    it "reports no failed item for a worker that had none in flight" do
      worker.current = nil
      worker.done = 1
      results = {}
      pool.send(:replace, worker, [], [], results, [])
      expect([results, seen]).to eq([{}, []])
    end

    it "starts a replacement on the same number and hands it the queue" do
      worker.done = 1
      workers = []
      queue = [8]
      pool.send(:replace, worker, workers, queue, {}, [1])
      expect(pool).to have_received(:start).with(3, [1], workers)
      expect(workers).to eq([fresh])
      expect(pool).to have_received(:assign).with(fresh, queue)
    end

    it "gives up only when the worker never finished an item" do
      worker.done = 1
      pool.instance_variable_set(:@start_failures, 2)
      expect { pool.send(:replace, worker, [], [], {}, []) }.not_to raise_error
      worker.done = 0
      pool.instance_variable_set(:@start_failures, 2)
      expect { pool.send(:replace, worker, [], [], {}, []) }.to raise_error(Saboteur::Error, /oom/)
    end

    it "starts nothing once halted, whatever is queued, and never gives up" do
      pool.halt!(drain: false)
      pool.instance_variable_set(:@start_failures, 2)
      expect { pool.send(:replace, worker, [], [8], {}, []) }.not_to raise_error
      expect(pool).not_to have_received(:start)
    end

    it "starts nothing when the queue is empty" do
      worker.done = 1
      pool.send(:replace, worker, [], [], {}, [])
      expect(pool).not_to have_received(:start)
    end
  end

  describe "#assign and #drain" do
    it "writes the next item to the worker and flushes it" do
      commands = instance_double(IO, puts: nil, flush: nil)
      worker.commands = commands
      pool.send(:assign, worker, [7, 8])
      expect(commands).to have_received(:puts).with(7)
      expect(commands).to have_received(:flush)
      expect(worker.current).to eq(7)
    end

    it "puts an item back when the worker's pipe is already gone" do
      worker.commands = instance_double(IO)
      allow(worker.commands).to receive(:puts).and_raise(Errno::EPIPE)
      queue = [8]
      pool.send(:assign, worker, queue)
      expect([queue, worker.current]).to eq([[8], nil])
    end

    it "reads nothing from a closed result pipe" do
      reader, writer = IO.pipe
      reader.close
      writer.close
      worker.results = reader
      expect(pool.send(:drain, worker, {})).to be_nil
    end
  end
end
