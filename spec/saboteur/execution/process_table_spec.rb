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

  describe "Darwin.all_pids", if: described_class::Darwin.available? do
    # A stand-in for proc_listallpids: fills the buffer like the kernel does.
    def fake_list(pids, calls)
      lambda do |buffer, size|
        calls << (size / 4)
        fitting = pids.first(size / 4)
        buffer[0, fitting.size * 4] = fitting.pack("l*")
        [pids.size, size / 4].min
      end
    end

    it "retries with a bigger buffer when the kernel fills it" do
      calls = []
      pids = (1..50).to_a
      expect(described_class::Darwin.all_pids(fake_list(pids, calls), 16)).to eq(pids)
      expect(calls).to eq([16, 32, 64])
    end

    it "raises instead of guessing when the kernel reports an error" do
      expect { described_class::Darwin.all_pids(->(_buffer, _size) { -1 }, 16) }
        .to raise_error(SystemCallError)
    end
  end

  it "falls back to ps when the fast backend fails, so containment never goes blind" do
    allow(described_class.backend).to receive(:snapshot).and_raise(SystemCallError.new("boom", 5))
    expect(described_class.snapshot.fetch(Process.pid).pid).to eq(Process.pid) unless described_class.backend ==
                                                                                      described_class::Ps
  end

  it "picks the fastest backend this platform supports" do
    expected = if RUBY_PLATFORM.include?("darwin") then described_class::Darwin
               elsif File.exist?("/proc/self/stat") then described_class::Linux
               else described_class::Ps
               end
    expect(described_class.backend).to eq(expected)
  end
end
