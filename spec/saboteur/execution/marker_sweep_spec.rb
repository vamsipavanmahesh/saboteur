# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rbconfig"

RSpec.describe Saboteur::Execution::MarkerSweep do
  let(:marker) { "abcd1234ef01" }
  let(:env_var) { "SABOTEUR_MARKER_SPEC" }

  def spawn_with(env, &block)
    Process.spawn(env, RbConfig.ruby, "-e", "sleep 30", &block)
  end

  after do
    @pids&.each { |pid| Process.kill("KILL", pid) rescue nil } # rubocop:disable Style/RescueModifier
  end

  it "finds an exec'd process by the marker frozen into its environment (#365)" do
    skip "needs /proc/*/environ" unless described_class.available?
    @pids = [spawn_with(env_var => "other:#{marker}")]
    expect(described_class.marked_pids(marker, env_var)).to include(@pids.first)
  end

  it "ignores a process whose marker list names another run" do
    skip "needs /proc/*/environ" unless described_class.available?
    @pids = [spawn_with(env_var => "other1:other2")]
    expect(described_class.marked_pids(marker, env_var)).not_to include(@pids.first)
  end

  it "finds a fork-only process by its inherited comm, even without the env marker" do
    skip "needs /proc/*/environ" unless described_class.available?
    pid = fork do
      Process.setsid
      described_class.write_comm(marker)
      sleep 30
    end
    @pids = [pid]
    expect(described_class.marked_pids(marker, env_var)).to include(pid)
  end
end
