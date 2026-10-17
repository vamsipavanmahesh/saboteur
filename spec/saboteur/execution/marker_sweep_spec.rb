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
end
