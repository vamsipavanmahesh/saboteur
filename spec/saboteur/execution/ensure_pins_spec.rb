# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Pins the cleanup that ensure blocks do on the raising path: the warning
# switch, the Landlock directory handle and the supervisor's report pipes.
RSpec.describe "ensure cleanup" do
  describe Saboteur::Execution::Reevaluator do
    subject(:reevaluator) { described_class.new }

    it "restores $VERBOSE after the block, whether it returns or raises, and silences it inside" do
      original = $VERBOSE
      seen = nil
      reevaluator.send(:silencing_warnings) { seen = $VERBOSE }
      expect(seen).to be_nil
      expect($VERBOSE).to eq(original)
      expect { reevaluator.send(:silencing_warnings) { raise "boom" } }.to raise_error("boom")
      expect($VERBOSE).to eq(original)
    ensure
      $VERBOSE = original
    end

    it "restores a true $VERBOSE too" do
      original = $VERBOSE
      $VERBOSE = true
      expect { reevaluator.send(:silencing_warnings) { raise "boom" } }.to raise_error("boom")
      expect($VERBOSE).to be(true)
    ensure
      $VERBOSE = original
    end
  end

  describe Saboteur::Execution::Sandbox do
    let(:close) { double("close", call: 0) }
    let(:syscall) { double("syscall") }

    before do
      allow(described_class::LibC).to receive_messages(open_fn: double("open", call: 9), close_fn: close,
                                                       syscall_fn: syscall)
      allow(described_class).to receive(:last_errno).and_return(13)
    end

    it "closes the directory handle after it adds the rule" do
      allow(syscall).to receive(:call).and_return(0)
      described_class.send(:allow, 4, "/tmp", 1)
      expect(close).to have_received(:call).with(9).once
    end

    it "closes the directory handle when adding the rule fails" do
      allow(syscall).to receive(:call).and_return(-1)
      expect { described_class.send(:allow, 4, "/tmp", 1) }.to raise_error(SystemCallError)
      expect(close).to have_received(:call).with(9).once
    end
  end

  describe Saboteur::Execution::SupervisorBatch do
    subject(:batch) { Object.new.extend(described_class) }

    let(:readers) { Array.new(2) { IO.pipe.first } }
    let(:writers) { [] }
    let(:began) { 0.0 }
    let(:fatal) { Class.new(Exception) } # rubocop:disable Lint/InheritException

    after { readers.each { |io| io.close unless io.closed? } }

    def part(raising: false)
      double("part").tap do |double|
        allow(double).to receive(:contain) { raising ? raise(fatal, "contain failed") : :ok }
        allow(double).to receive(:signal)
      end
    end

    def started(*parts)
      parts.each_with_index.map { |item, index| [item, 100 + index, readers[index], began] }
    end

    it "closes each report pipe once its watcher is done, whether it returned or raised" do
      watchers = batch.send(:start_watchers, started(part, part(raising: true)), 1)
      outcomes = watchers.map(&:value)
      expect(outcomes.last).to be_a(Exception)
      expect(readers).to all(be_closed)
    end

    it "closes every report pipe when it reaps started children, including one whose containment raises" do
      batch.send(:reap_started, started(part(raising: true), part))
      expect(readers).to all(be_closed)
    end
  end

  describe Saboteur::Execution::Supervisor do
    it "closes the report pipe when containment raises" do
      supervisor = described_class.new(limits: described_class::Limits.default)
      pipes = []
      allow(IO).to(receive(:pipe).and_wrap_original { |original| original.call.tap { |pair| pipes << pair.first } })
      allow(supervisor).to receive(:contain) do |pid, *|
        Process.kill("KILL", pid)
        Process.wait(pid)
        raise "contain failed"
      end
      expect { supervisor.run(timeout: 5, &:close) }.to raise_error("contain failed")
      expect(pipes.first).to be_closed
    end
  end
end
