# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rbconfig"

RSpec.describe Saboteur::Execution::MarkerSweep do
  let(:marker) { "abcd1234ef01" }
  let(:env_var) { "SABOTEUR_MARKER_SPEC" }

  # Spawns `ruby -e` with env and returns its pid plus a pipe the child
  # writes to once it runs, so the sweep never races the exec that freezes
  # the marker into /proc/<pid>/environ (the pipe, not a sleep, is what
  # makes the scan deterministic on a loaded machine).
  def spawn_with(env)
    ready_r, ready_w = IO.pipe
    pid = Process.spawn(env, RbConfig.ruby, "-e", '$stdout.write("R"); $stdout.flush; sleep 30', out: ready_w)
    ready_w.close
    [pid, ready_r]
  end

  after do
    @pids&.each { |pid| Process.kill("KILL", pid) rescue nil } # rubocop:disable Style/RescueModifier
  end

  it "finds an exec'd process by the marker frozen into its environment (#365)" do
    skip "needs /proc/*/environ" unless described_class.available?
    pid, ready = spawn_with(env_var => "other:#{marker}")
    @pids = [pid]
    ready.getbyte
    expect(described_class.marked_pids(marker, env_var)).to include(pid)
  end

  it "ignores a process whose marker list names another run" do
    skip "needs /proc/*/environ" unless described_class.available?
    pid, ready = spawn_with(env_var => "other1:other2")
    @pids = [pid]
    ready.getbyte
    expect(described_class.marked_pids(marker, env_var)).not_to include(pid)
  end

  it "finds a fork-only process by its inherited comm, even without the env marker" do
    skip "needs /proc/*/environ" unless described_class.available?
    ready_r, ready_w = IO.pipe
    pid = fork do
      ready_r.close
      Process.setsid
      described_class.write_comm(marker)
      # Never calls write_comm: its comm is the inherited copy, and its
      # frozen environ comes from the spec run's exec - no marker there.
      grandchild = fork { sleep 30 }
      ready_w.puts(grandchild)
      ready_w.close
      Process.detach(grandchild)
      sleep 30
    end
    ready_w.close
    grandchild = ready_r.gets.to_i
    @pids = [pid, grandchild]
    expect(described_class.marked_pids(marker, env_var)).to include(grandchild)
  end

  describe "against a stubbed /proc" do
    let(:comm_name) { "#{Saboteur::Execution::Supervisor::COMM_PREFIX}#{marker}" }
    let(:comms) { {} }
    let(:environs) { {} }
    let(:names) { [] }

    before do
      allow(Dir).to receive(:children).and_call_original
      allow(Dir).to receive(:children).with("/proc") { names }
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(%r{\A/proc/\d+/comm\z}) do |path|
        comms.fetch(path[/\d+/].to_i) { raise Errno::ENOENT, path }
      end
      allow(File).to receive(:binread).and_call_original
      allow(File).to receive(:binread).with(%r{\A/proc/\d+/environ\z}) do |path|
        environs.fetch(path[/\d+/].to_i) { raise Errno::ENOENT, path }
      end
    end

    it "says whether /proc/self/environ exists, for exactly that path" do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("/proc/self/environ").and_return(true)
      expect(described_class.available?).to be(true)
      allow(File).to receive(:exist?).with("/proc/self/environ").and_return(false)
      expect(described_class.available?).to be(false)
    end

    it "keeps only all-digit entries, whole, and never the sweeping process itself" do
      own = Process.pid
      names.replace(["self", "12abc", "abc12", "", "7", own.to_s])
      [0, 12, 7, own].each { |pid| comms[pid] = comm_name }
      expect(described_class.marked_pids(marker, env_var)).to eq([7])
    end

    it "skips a process that exits mid-sweep and keeps the others" do
      names.replace(%w[21 22])
      comms[22] = comm_name
      expect(described_class.marked_pids(marker, env_var)).to eq([22])
    end

    it "reads the marker from the variable named env_var, not from a longer name sharing its prefix" do
      names.replace(["31"])
      comms[31] = "other"
      environs[31] = "#{env_var}_LONG=zzz\0#{env_var}=#{marker}\0"
      expect(described_class.marked_pids(marker, env_var)).to eq([31])
    end

    it "matches the marker as a whole entry of the colon list, never as a substring" do
      names.replace(%w[41 42 43])
      comms.merge!(41 => "x", 42 => "x", 43 => "x")
      environs[41] = "#{env_var}=a:x#{marker}x\0"
      environs[42] = "#{env_var}=#{marker}:b\0"
      environs[43] = "PATH=/bin\0"
      expect(described_class.marked_pids(marker, env_var)).to eq([42])
    end

    it "answers false, not nil, for a process without the variable or the marker" do
      environs[51] = "PATH=/bin\0"
      environs[52] = "#{env_var}=other\0"
      expect(described_class.environ_marked?(51, "#{env_var}=", marker)).to be(false)
      expect(described_class.environ_marked?(52, "#{env_var}=", marker)).to be(false)
      environs[53] = "#{env_var}=#{marker}\0"
      expect(described_class.environ_marked?(53, "#{env_var}=", marker)).to be(true)
    end
  end
end
