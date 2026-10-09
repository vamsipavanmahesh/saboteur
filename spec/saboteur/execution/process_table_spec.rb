# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Execution::ProcessTable do
  def with_child(group: false)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      Process.setpgid(0, 0) if group
      writer.puts("ready")
      sleep 10
    end
    writer.close
    reader.gets
    yield pid
  ensure
    begin
      Process.kill("KILL", pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end

  described_class.backends.each do |backend|
    context "with the #{backend.name.split('::').last} backend" do
      let(:snapshot) { backend.snapshot }

      it "lists this process with its parent and group" do
        me = snapshot.fetch(Process.pid)
        expect([me.ppid, me.pgid]).to eq([Process.ppid, Process.getpgrp])
        expect(me.rss_kb).to be_positive
        expect(me.zombie).to be(false)
      end

      it "sees a forked child, its own process group, and a stable start time" do
        with_child(group: true) do |pid|
          first = backend.snapshot.fetch(pid)
          expect([first.ppid, first.pgid]).to eq([Process.pid, pid])
          expect(backend.snapshot.fetch(pid).started).to eq(first.started)
        end
      end

      it "marks an exited, unreaped child as a zombie" do
        pid = fork { exit!(0) }
        sleep 0.2
        expect(backend.snapshot[pid]&.zombie).to be(true)
      ensure
        Process.wait(pid)
      end

      it "agrees with the portable ps backend on parent and group" do
        with_child do |pid|
          mine = backend.snapshot.fetch(pid)
          portable = described_class::Ps.snapshot.fetch(pid)
          expect([mine.ppid, mine.pgid]).to eq([portable.ppid, portable.pgid])
        end
      end
    end
  end

  it "picks the fastest backend this platform supports" do
    expected = if RUBY_PLATFORM.include?("darwin") then described_class::Darwin
               elsif File.exist?("/proc/self/stat") then described_class::Linux
               else described_class::Ps
               end
    expect(described_class.backend).to eq(expected)
  end
end
