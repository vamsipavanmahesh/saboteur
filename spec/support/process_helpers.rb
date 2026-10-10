# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Whether a process is still running. On Linux the test process is a child
# subreaper (it creates Supervisors), so processes orphaned by a test end up
# as its own zombies: dead, but still visible to kill(0). A zombie counts as
# dead, and one that is ours is reaped on the way.
module ProcessHelpers
  def alive?(pid)
    reap_if_ours(pid)
    Process.kill(0, pid)
    !zombie?(pid)
  rescue Errno::ESRCH
    false
  end

  # Pids of this process's children (zombies included) that the block left
  # behind. Only new ones count: on Linux this process is a subreaper, so
  # orphans of other examples may still be arriving or dying here.
  def children_left_by
    before = own_children
    yield
    own_children - before
  end

  private

  def own_children
    Saboteur::Execution::ProcessTable.snapshot.values.select { |entry| entry.ppid == Process.pid }.map(&:pid)
  end

  def reap_if_ours(pid)
    Process.waitpid(pid, Process::WNOHANG)
  rescue Errno::ECHILD
    nil
  end

  def zombie?(pid)
    stat = "/proc/#{pid}/stat"
    return false unless File.exist?(stat)

    # The state is the first field after the parenthesised command name.
    File.read(stat).split(") ", 2).last.to_s.start_with?("Z")
  rescue SystemCallError
    false
  end
end

RSpec.configure { |config| config.include ProcessHelpers }
