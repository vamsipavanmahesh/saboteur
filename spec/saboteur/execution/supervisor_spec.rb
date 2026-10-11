# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rbconfig"
require "tmpdir"

# Every example here is self-limiting: children sleep or allocate a bounded
# amount, so a regression fails the example instead of exhausting the machine.
RSpec.describe Saboteur::Execution::Supervisor do
  let!(:dir) { Dir.mktmpdir("saboteur-supervisor-") }
  let(:limits) { described_class::Limits.default }
  let(:supervisor) { described_class.new(limits:) }

  # Safety net: if a containment regression lets a process survive, kill it
  # here so the failure stays a failure and not a leak.
  after do
    Dir[File.join(dir, "*.pid")].flat_map { |file| File.read(file).split(",") }.each do |pid|
      Process.kill("KILL", pid.to_i)
    rescue Errno::ESRCH, Errno::EPERM, ArgumentError
      nil
    end
    FileUtils.rm_rf(dir)
  end

  # Orphans are reaped asynchronously; give it a moment.
  def dead_within?(pid, seconds)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    sleep 0.05 while alive?(pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    !alive?(pid)
  end

  def pid_file(name)
    File.join(dir, "#{name}.pid")
  end

  def read_pid(name)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    sleep 0.02 until File.size?(pid_file(name)) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    File.read(pid_file(name)).to_i
  end

  it "returns what the child wrote and how it exited" do
    result = supervisor.run(timeout: 5) { |writer| writer.write("hello") }
    expect([result.payload, result.stopped_by, result.exit_status.exitstatus]).to eq(["hello", nil, 0])
  end

  it "calls on_tick from the parent's wait loop while the child runs" do
    ticks = 0
    result = supervisor.run(timeout: 5, on_tick: -> { ticks += 1 }) do |writer|
      sleep 1.2
      writer.write("hello")
    end
    expect(result.payload).to eq("hello")
    expect(ticks).to be >= 1
  end

  # A raising on_tick (progress IO failed) must not leave the child running
  # unsupervised: containment kills and reaps it before the error propagates.
  it "kills and reaps the child when on_tick raises" do
    pid_file = File.join(dir, "child.pid")
    # Raise only once the child is up, so the kill has a live target.
    on_tick = -> { raise Errno::EPIPE, "broken pipe" if File.exist?(pid_file) }
    expect do
      supervisor.run(timeout: 30, on_tick: on_tick) do |_writer|
        File.write(pid_file, Process.pid)
        sleep 30
      end
    end.to raise_error(Errno::EPIPE)
    pid = File.read(pid_file).to_i
    expect(pid).to be_positive
    expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    expect(described_class.live).to be_empty
  end

  it "records nesting depth in the child" do
    nested = supervisor.run(timeout: 5) do |writer|
      writer.write(described_class.new.run(timeout: 5) { |inner| inner.write(ENV.fetch(described_class::CHILD_ENV)) }
                                   .payload)
    end
    outer_depth = ENV.fetch(described_class::CHILD_ENV, "0").to_i
    expect(nested.payload).to eq((outer_depth + 2).to_s)
  end

  it "refuses to fork past the maximum depth, even if every other guard is gone" do
    stub_const("ENV", ENV.to_h.merge(described_class::CHILD_ENV => described_class::MAX_DEPTH.to_s))
    expect { supervisor.run(timeout: 5) { nil } }.to raise_error(Saboteur::Error, /nested .* deep/)
  end

  it "marks the child so a nested saboteur run can refuse to start" do
    before = ENV.fetch(described_class::CHILD_ENV, nil) # set when this suite itself runs under saboteur
    result = supervisor.run(timeout: 5) { |writer| writer.write(ENV.fetch(described_class::CHILD_ENV, "unset")) }
    expect(result.payload).to eq((before.to_i + 1).to_s)
    expect(ENV.fetch(described_class::CHILD_ENV, nil)).to eq(before)
  end

  it "kills a grandchild that left the process group (what a nested runner does)" do
    result = supervisor.run(timeout: 1) do
      fork do
        Process.setpgid(0, 0)
        File.write(pid_file("escaped"), Process.pid.to_s)
        sleep 30
      end
      sleep 30
    end
    expect(result.stopped_by).to eq(:timeout)
    expect(dead_within?(read_pid("escaped"), 3)).to be(true)
  end

  it "contains a supervisor running inside its own child (recursion), including the CPU limit it inherits" do
    result = supervisor.run(timeout: 1) do
      described_class.new.run(timeout: 60) do
        File.write(pid_file("inner"), Process.pid.to_s)
        sleep 30
      end
    end
    expect(result.stopped_by).to eq(:timeout)
    expect(dead_within?(read_pid("inner"), 3)).to be(true)
  end

  it "kills what a child leaves running after it exits normally, and reports it" do
    result = supervisor.run(timeout: 5) do
      pid = Process.spawn("sleep", "30", pgroup: true)
      File.write(pid_file("daemon"), pid.to_s)
      sleep 0.7 # let the supervisor see it in the tree
    end
    leftover = read_pid("daemon")
    expect(result.stopped_by).to be_nil
    expect(result.leftover_pids).to include(leftover)
    expect(dead_within?(leftover, 3)).to be(true)
  end

  context "with a memory cap" do
    let(:limits) { described_class::Limits.new(max_memory_mb: 150, max_processes: 64) }

    it "stops a child whose memory grows past the cap, long before the deadline" do
      result = supervisor.run(timeout: 20) do
        hog = []
        # Bounded at ~1.5 GB even if the cap were ignored.
        150.times do
          hog << ("x" * 10_000_000)
          sleep 0.02
        end
        sleep 30
      end
      expect(result.stopped_by).to eq(:memory)
      expect(result.detail).to match(/grew by \d+ MB \(limit 150 MB\)/)
      expect(result.runtime).to be < 10
    end
  end

  context "with a process cap" do
    let(:limits) { described_class::Limits.new(max_memory_mb: 2048, max_processes: 10) }

    it "stops a child that keeps forking, and kills every process it made" do
      result = supervisor.run(timeout: 20) do
        pids = Array.new(30) do
          sleep 0.03
          fork { sleep 30 }
        end
        File.write(pid_file("forks"), pids.join(","))
        sleep 30
      end
      expect(result.stopped_by).to eq(:processes)
      forks = begin
        File.read(pid_file("forks")).split(",").map(&:to_i)
      rescue StandardError
        []
      end
      expect(forks.select { |pid| alive?(pid) }).to be_empty
      expect(result.leftover_pids.size).to be >= 10
    end
  end

  # macOS over-counts CPU time for a process with many waking threads and
  # sends SIGXCPU early (measured: at 5.4 s of a 20 s limit with 20 threads
  # waking every 10 ms). A Rails test child has ~20 threads.
  it "ignores a SIGXCPU that comes before the child used its CPU budget" do
    result = supervisor.run(timeout: 5, cpu_seconds: 3) do |writer|
      Process.kill("XCPU", Process.pid)
      sleep 0.2
      writer.write("ok")
    end
    expect([result.payload, result.exit_status.exitstatus]).to eq(["ok", 0])
  end

  it "stops a child that really used its CPU budget with SIGXCPU" do
    result = supervisor.run(timeout: 10, cpu_seconds: 1) { loop { nil } }
    expect(Signal.signame(result.exit_status.termsig)).to eq("XCPU")
  end

  it "bounds an orphan it never saw with the inherited CPU limit" do
    # The intermediate process exits at once, so the spinner is re-parented
    # to init before the first poll and is not in the tracked tree.
    supervisor.run(timeout: 5, cpu_seconds: 1) do
      fork do
        Process.setsid
        fork do
          File.write(pid_file("spinner"), Process.pid.to_s)
          loop { nil }
        end
        exit!(0)
      end
    end
    expect(dead_within?(read_pid("spinner"), 6)).to be(true)
  end

  describe "when the supervising process goes away" do
    let(:script) do
      <<~RUBY
        require "saboteur"
        Saboteur::Execution::Supervisor.new.run(timeout: 60) do
          File.write(#{pid_file('child').inspect}, Process.pid.to_s)
          sleep 60
        end
      RUBY
    end

    def start_supervisor
      Process.spawn(RbConfig.ruby, "-I", File.expand_path("../../../lib", __dir__), "-e", script)
    end

    it "kills its children on INT" do
      parent = start_supervisor
      child = read_pid("child")
      Process.kill("INT", parent)
      Process.wait(parent)
      expect(dead_within?(child, 3)).to be(true)
    end

    it "lets children notice a SIGKILLed supervisor and exit" do
      parent = start_supervisor
      child = read_pid("child")
      Process.kill("KILL", parent)
      Process.wait(parent)
      expect(dead_within?(child, 4)).to be(true)
    end
  end
end
