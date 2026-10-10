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

  private

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
