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
  # A leftover live entry is a containment leak: name the example that left it.
  after do
    leftovers = described_class.live
    expect(leftovers).to be_empty, lambda {
      details = leftovers.map { |pid, tree| "#{pid} => #{tree.inspect}" }
      "Supervisor.live leaked: #{details.join(', ')}"
    }
  end

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

  # The child closes its pipe (EOF) a moment before it finishes exiting, as a
  # real suite does when at_exit handlers run. The supervisor must wait for
  # that exit instead of SIGKILLing a child that already reported.
  it "lets a child that already delivered its result finish exiting" do
    result = supervisor.run(timeout: 5) do |writer|
      writer.write("done")
      writer.close
      sleep 0.3
    end
    expect(result.payload).to eq("done")
    expect(result.exit_status).to be_success
    expect(result.supervisor_killed).to be(false)
  end

  it "keeps the payload and reports its own kill when the child never exits after EOF" do
    stub_const("#{described_class}::POST_EOF_GRACE", 0.3)
    result = supervisor.run(timeout: 10) do |writer|
      writer.write("done")
      writer.close
      sleep 30
    end
    expect(result.payload).to eq("done")
    expect(result.supervisor_killed).to be(true)
    expect(result.exit_status.termsig).to eq(Signal.list.fetch("KILL"))
  end

  it "does not mark a child that died by itself as killed by the supervisor" do
    result = supervisor.run(timeout: 5) do |writer|
      writer.write("partial")
      writer.close
      Process.kill("KILL", Process.pid)
      sleep
    end
    expect(result.supervisor_killed).to be(false)
    expect(result.exit_status.termsig).to eq(Signal.list.fetch("KILL"))
  end

  it "reports memory pressure only when the tree grew toward the limit" do
    quiet = supervisor.run(timeout: 5) { |writer| writer.write("ok") }
    expect(quiet.memory_pressure).to be(false)
  end

  # The grace wait ends with the child "still running", then the child ends
  # on its own before the supervisor acts. Its real cause of death must
  # survive: stubbing the wait makes the window deterministic.
  context "when the child ends by itself right after the grace wait gave up" do
    before do
      allow(supervisor).to receive(:await_exit) do |*|
        sleep 0.8
        [nil, nil, nil, true]
      end
    end

    it "keeps a non-zero exit and does not blame the supervisor" do
      result = supervisor.run(timeout: 10) do |writer|
        writer.write("done")
        writer.close
        sleep 0.2
        exit!(7)
      end
      expect(result.exit_status.exitstatus).to eq(7)
      expect(result.supervisor_killed).to be(false)
      expect(result.child_failed?).to be(true)
    end

    it "keeps an external SIGKILL and does not blame the supervisor" do
      result = supervisor.run(timeout: 10) do |writer|
        writer.write("done")
        writer.close
        sleep 0.2
        Process.kill("KILL", Process.pid)
        sleep
      end
      expect(result.exit_status.termsig).to eq(Signal.list.fetch("KILL"))
      expect(result.supervisor_killed).to be(false)
      expect(result.child_failed?).to be(true)
    end

    it "blames the supervisor only for a child it saw alive and then killed" do
      result = supervisor.run(timeout: 10) do |writer|
        writer.write("done")
        writer.close
        sleep 30
      end
      expect(result.supervisor_killed).to be(true)
      expect(result.child_failed?).to be(false)
    end
  end

  context "while waiting for a child that already reported" do
    let(:limits) { described_class::Limits.new(max_memory_mb: 2048, max_processes: 3) }

    it "still enforces the process cap and reports the stop" do
      stub_const("#{described_class}::POST_EOF_GRACE", 10)
      result = supervisor.run(timeout: 20) do |writer|
        writer.write("done")
        writer.close
        pids = Array.new(8) { fork { sleep 30 } }
        File.write(pid_file("forks"), pids.join(","))
        sleep 30
      end
      expect(result.payload).to eq("done")
      expect(result.stopped_by).to eq(:processes)
      expect(result.runtime).to be < 8
    end

    it "keeps calling on_tick" do
      stub_const("#{described_class}::POST_EOF_GRACE", 1.5)
      ticks = 0
      supervisor.run(timeout: 20, on_tick: -> { ticks += 1 }) do |writer|
        writer.write("done")
        writer.close
        sleep 30
      end
      expect(ticks).to be >= 1
    end

    it "still reports a timeout that falls inside the grace window" do
      stub_const("#{described_class}::POST_EOF_GRACE", 30)
      result = supervisor.run(timeout: 1) do |writer|
        writer.write("done")
        writer.close
        sleep 30
      end
      expect(result.stopped_by).to eq(:timeout)
    end

    it "kills and reaps the child when on_tick raises during the grace window" do
      stub_const("#{described_class}::POST_EOF_GRACE", 10)
      pid_path = pid_file("child")
      # Same handshake guard as the on_tick example below (#277): the file's
      # existence can precede its bytes, and raising in that window reads an
      # empty file (pid 0) after the kill - kill(0, 0) checks our own process
      # group, so the dead_within? wait then "sees" the child alive forever.
      on_tick = -> { raise Errno::EPIPE, "broken pipe" if File.exist?(pid_path) && File.read(pid_path).to_i.positive? }
      expect do
        supervisor.run(timeout: 30, on_tick: on_tick) do |writer|
          writer.write("done")
          writer.close
          File.write(pid_path, Process.pid)
          sleep 30
        end
      end.to raise_error(Errno::EPIPE)
      pid = File.read(pid_path).to_i
      expect(pid).to be_positive
      expect(dead_within?(pid, 5)).to be(true)
    end
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
    # Raise only once the child is up and its pid is fully written: the file's
    # existence can precede its bytes, and triggering in that window reads an
    # empty file (0) after the kill (#277).
    on_tick = -> { raise Errno::EPIPE, "broken pipe" if File.exist?(pid_file) && File.read(pid_file).to_i.positive? }
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

  # Fault injection for #762: the CI flake where Supervisor.live kept a
  # ProcessTree entry after a run. When the process table is unreadable
  # (ProcessTable.snapshot raises through kill_all_except), containment must
  # still kill and reap the child and unregister it, or the entry leaks and
  # the child runs unsupervised.
  it "still kills, reaps and unregisters the child when the process table is unreadable (#762)" do
    pid_file = File.join(dir, "child.pid")
    # Fail the table only once the child is up and its pid fully written
    # (same window as #277): before that the run must proceed normally.
    real_snapshot = Saboteur::Execution::ProcessTable.method(:snapshot)
    allow(Saboteur::Execution::ProcessTable).to receive(:snapshot) do
      raise Errno::EIO, "ps failed" if File.exist?(pid_file) && File.read(pid_file).to_i.positive?

      real_snapshot.call
    end
    expect do
      supervisor.run(timeout: 30) do |_writer|
        File.write(pid_file, Process.pid)
        sleep 30
      end
    end.to raise_error(Errno::EIO)
    pid = File.read(pid_file).to_i
    expect(pid).to be_positive
    expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    expect(described_class.live).to be_empty
  end

  # Fail-closed, not fail-open: when the table goes blind only at release
  # time (watch saw a healthy table), the run must surface the scan error
  # instead of returning a clean Result the guards would read as no leak.
  it "does not return a clean Result when the release-time table scan fails (#762)" do
    real_snapshot = Saboteur::Execution::ProcessTable.method(:snapshot)
    allow(Saboteur::Execution::ProcessTable).to receive(:snapshot) do
      raise Errno::EIO, "ps failed" if caller_locations(1, 30).any? { |loc| loc.base_label == "kill_all_except" }

      real_snapshot.call
    end
    expect do
      supervisor.run(timeout: 30) { |writer| writer.write("hello") }
    end.to raise_error(Errno::EIO)
    expect(described_class.live).to be_empty
  end

  # The group kill is what ends a grandchild when the release-time scan is
  # blind: the table-driven sweep is lost, the child's own group is not. Each
  # error class the backends raise (a failed ps, a libproc load failure) must
  # take the same containment path, and the scan error must still surface.
  [Errno::EIO, Fiddle::DLError].each do |error|
    it "kills the child's group and surfaces the scan error when the release scan raises #{error} (#762)" do
      real_snapshot = Saboteur::Execution::ProcessTable.method(:snapshot)
      blind_reads = 0
      allow(Saboteur::Execution::ProcessTable).to receive(:snapshot) do
        if caller_locations(1, 30).any? { |loc| loc.base_label == "kill_all_except" }
          blind_reads += 1
          raise error, "table blind"
        end

        real_snapshot.call
      end

      expect do
        supervisor.run(timeout: 30) do |writer|
          File.write(pid_file("grand"), Process.spawn("sleep", "30").to_s)
          writer.write("done")
        end
      end.to raise_error(error, /table blind/)

      expect(blind_reads).to be_positive
      expect(dead_within?(read_pid("grand"), 5)).to be(true)
      expect(described_class.live).to be_empty
    end
  end

  it "records a child exception on stderr before exiting, so an empty result has a cause (#255)" do
    expect do
      supervisor.run(timeout: 5) { |_writer| raise "boom in child" }
    end.to output(/supervised child died: RuntimeError: boom in child/).to_stderr_from_any_process

    expect do
      supervisor.run(timeout: 5) { |_writer| raise "boom in child" }
    end.to output(/from .*supervisor_spec\.rb/).to_stderr_from_any_process
  end

  it "still exits 1 when the dying child's stderr is closed, without running at_exit hooks (#289)" do
    marker = File.join(dir, "at_exit.txt")
    result = supervisor.run(timeout: 5) do |_writer|
      at_exit { File.write(marker, "ran") }
      $stderr.close
      raise "boom"
    end
    expect(result.payload).to eq("")
    expect(result.exit_status.exitstatus).to eq(1)
    expect(File.exist?(marker)).to be(false)
  end

  it "keeps the dying child's voice off stdout, so agent JSON stays parseable (#289)" do
    expect do
      supervisor.run(timeout: 5) { |_writer| raise "boom" }
    end.not_to output.to_stdout_from_any_process
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

  it "still runs the child when its process-group change is refused (#296)" do
    allow(Process).to receive(:setpgid).and_raise(Errno::EPERM)
    result = supervisor.run(timeout: 5) { |writer| writer.write("ok") }
    expect(result.payload).to eq("ok")
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
    expect(result.leftover_notes.join(" ")).to include(leftover.to_s).and include("sleep")
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

  it "kills a sleeping orphan it never saw, not just a spinning one (#365)" do
    # Same escape as the CPU-bound orphan above - setsid, intermediate
    # exits before the first poll - but a sleeper burns no CPU, so only the
    # marker sweep can end it. Linux only: the sweep reads /proc/*/environ.
    skip "needs /proc/*/environ" unless Saboteur::Execution::MarkerSweep.available?
    result = supervisor.run(timeout: 5) do
      fork do
        Process.setsid
        fork do
          File.write(pid_file("sleeper"), Process.pid.to_s)
          sleep 30
        end
        exit!(0)
      end
    end
    expect(result.leftover_pids).to include(read_pid("sleeper"))
    expect(dead_within?(read_pid("sleeper"), 3)).to be(true)
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

  describe "#run_many (#741)" do
    it "returns every child's result in index order and tells each child its index" do
      results = supervisor.run_many(3, timeout: 10) { |writer, index| writer.write("part #{index}") }

      expect(results.map(&:payload)).to eq(["part 0", "part 1", "part 2"])
      expect(results.map { |result| result.exit_status.exitstatus }).to eq([0, 0, 0])
      expect(results.map(&:stopped_by)).to eq([nil, nil, nil])
    end

    # A barrier, not a stopwatch: each child checks in and waits for all
    # three. Children run one after another never see the third check-in
    # (the first gives up after the cap), however fast the machine is.
    it "supervises the children at the same time, not one after another" do
      Dir.mktmpdir do |dir|
        results = supervisor.run_many(3, timeout: 30) do |writer, index|
          FileUtils.touch(File.join(dir, "child-#{index}"))
          give_up = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
          sleep 0.01 until Dir.children(dir).size == 3 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > give_up
          writer.write(Dir.children(dir).size.to_s)
        end

        expect(results.map(&:payload)).to eq(%w[3 3 3])
      end
    end

    it "gives each child its own marker and keeps siblings' payloads apart" do
      results = supervisor.run_many(3, timeout: 10) do |writer, _index|
        writer.write(ENV.fetch(described_class::TREE_ENV).split(":").last)
      end

      expect(results.map(&:payload).uniq.size).to eq(3)
    end

    it "stops only the child that exceeds its deadline" do
      results = supervisor.run_many(2, timeout: 1) do |writer, index|
        index.zero? ? sleep(30) : writer.write("done")
      end

      expect(results.map(&:stopped_by)).to eq([:timeout, nil])
      expect(results.last.payload).to eq("done")
      expect(described_class.live).to be_empty
    end

    it "calls on_tick only from the calling thread" do
      threads = []
      supervisor.run_many(2, timeout: 10, on_tick: -> { threads << Thread.current }) do |writer, _index|
        sleep 0.3
        writer.write("ok")
      end

      expect(threads).not_to be_empty
      expect(threads.uniq).to eq([Thread.current])
    end

    it "kills a child's group when the process table is blind and on_tick raises" do
      # The table goes blind only once on_tick has raised, so the failure
      # that reaches containment is always the tick's, never the stub's: a
      # wall-clock condition (the pid file exists) let the 0.5 s usage poll
      # hit the stub first on a loaded runner.
      real_snapshot = Saboteur::Execution::ProcessTable.method(:snapshot)
      tick_raised = false
      blind_reads = 0
      allow(Saboteur::Execution::ProcessTable).to receive(:snapshot) do
        if tick_raised
          blind_reads += 1
          raise Errno::EIO, "ps failed"
        end

        real_snapshot.call
      end
      ticks = 0
      on_tick = lambda do
        next unless File.size?(pid_file("grand")) && (ticks += 1) > 3

        tick_raised = true
        raise "tick failed"
      end

      expect do
        supervisor.run_many(1, timeout: 30, on_tick: on_tick) do |_writer, _index|
          File.write(pid_file("grand"), Process.spawn("sleep", "30").to_s)
          sleep 30
        end
      end.to raise_error(RuntimeError, "tick failed")

      # The table really was blind while the child was contained: without
      # this, a stub that never fires would leave the example green.
      expect(blind_reads).to be_positive
      expect(dead_within?(read_pid("grand"), 5)).to be(true)
    end

    it "does not signal a child whose watcher has already finished (its pid may be reused)" do
      finished = double("finished part")
      running = double("running part")
      allow(running).to receive(:signal)
      expect(finished).not_to receive(:signal)
      started = [[finished, 10, nil, 0], [running, 11, nil, 0]]

      supervisor.send(:kill_started, started,
                      [instance_double(Thread, alive?: false), instance_double(Thread, alive?: true)])

      expect(running).to have_received(:signal).with("KILL", -11)
      expect(running).to have_received(:signal).with("KILL", 11)
    end

    it "reaps, not only kills, the children already forked when a later fork fails" do
      calls = 0
      copy = supervisor.method(:dup)
      allow(supervisor).to receive(:dup) do
        if (calls += 1) == 3
          sleep 0.5 # let the first two children write their pid files
          raise IOError, "fork failed"
        end

        copy.call
      end

      expect do
        supervisor.run_many(3, timeout: 30) do |_writer, index|
          File.write(pid_file("reap#{index}"), Process.pid.to_s)
          sleep 30
        end
      end.to raise_error(IOError, "fork failed")

      %w[reap0 reap1].each do |name|
        expect { Process.waitpid(read_pid(name), Process::WNOHANG) }.to raise_error(Errno::ECHILD)
      end
      expect(described_class.live).to be_empty
    end

    it "stops every child at once when on_tick raises, well before their deadline" do
      ticks = 0
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      on_tick = -> { raise "tick failed" if (ticks += 1) > 20 }

      expect do
        supervisor.run_many(2, timeout: 12, on_tick: on_tick) do |_writer, index|
          File.write(pid_file("many#{index}"), Process.pid.to_s)
          sleep 30
        end
      end.to raise_error(RuntimeError, "tick failed")

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
      expect(dead_within?(read_pid("many0"), 5)).to be(true)
      expect(dead_within?(read_pid("many1"), 5)).to be(true)
      expect(described_class.live).to be_empty
    end

    it "kills the children already forked when a later fork fails, and keeps the original error" do
      calls = 0
      copy = supervisor.method(:dup)
      allow(supervisor).to receive(:dup) do
        if (calls += 1) == 3
          sleep 0.5 # let the first two children write their pid files
          raise IOError, "fork failed"
        end

        copy.call
      end
      allow_any_instance_of(described_class).to receive(:contain).and_raise("cleanup failed")

      expect do
        supervisor.run_many(3, timeout: 30) do |_writer, index|
          File.write(pid_file("fork#{index}"), Process.pid.to_s)
          sleep 30
        end
      end.to raise_error(IOError, "fork failed")

      expect(dead_within?(read_pid("fork0"), 5)).to be(true)
      expect(dead_within?(read_pid("fork1"), 5)).to be(true)
    end

    it "runs a single child" do
      results = supervisor.run_many(1, timeout: 5) { |writer, index| writer.write("only #{index}") }

      expect(results.map(&:payload)).to eq(["only 0"])
    end

    # The stub keeps the watcher from reaping, so the safety-net `after`
    # above kills the sleeping children through their pid files.
    it "re-raises a watcher's failure after every watcher has finished" do
      allow_any_instance_of(described_class).to receive(:contain).and_raise("watch failed")

      expect do
        supervisor.run_many(2, timeout: 10) do |_writer, index|
          File.write(pid_file("watch#{index}"), Process.pid.to_s)
          sleep 30
        end
      end.to raise_error(RuntimeError, "watch failed")
    end

    it "surfaces a failure to start a watcher as itself" do
      parent = Process.pid
      allow(Thread).to receive(:new).and_wrap_original do |original, *args, &block|
        next original.call(*args, &block) unless Process.pid == parent

        sleep 0.5 # let the child write its pid file
        raise ThreadError, "no thread"
      end

      expect do
        supervisor.run_many(1, timeout: 10) do |_writer, _index|
          File.write(pid_file("nothread"), Process.pid.to_s)
          sleep 30
        end
      end.to raise_error(ThreadError, "no thread")

      expect(dead_within?(read_pid("nothread"), 5)).to be(true)
    end

    it "refuses a count below 1" do
      expect { supervisor.run_many(0, timeout: 5) { nil } }
        .to raise_error(ArgumentError, "count must be at least 1, got 0")
    end
  end
end
