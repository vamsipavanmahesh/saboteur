# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "rbconfig"

# Reproduces the incident that froze a development machine: mutants that let
# a test start a real saboteur run inside a mutant child, whose children then
# escaped the process group. A watchdog bounds this example so a regression
# fails it instead of exhausting the machine.
RSpec.describe "containment of a test suite that starts saboteur", :e2e do
  let(:watchdog_max_processes) { 25 }
  let(:watchdog_seconds) { 120 }

  let(:dir) { copy_fixture("recursion") }

  def run_watched
    pid = Process.spawn({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") },
                        RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), E2EHelpers::EXE, "run",
                        chdir: dir, pgroup: true, out: File.join(dir, "out.txt"), err: File.join(dir, "err.txt"))
    tree = Saboteur::Execution::ProcessTree.new(pid)
    peak = 0
    tripped = nil
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + watchdog_seconds
    until Process.waitpid(pid, Process::WNOHANG)
      peak = [peak, tree.live_members.size].max
      if peak > watchdog_max_processes || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        tripped = "watchdog: #{peak} processes"
        tree.kill_all
        Process.wait(pid)
        break
      end
      sleep 0.1
    end
    leftover_pids = tree.live_members
    tree.kill_all
    [peak, tripped, leftover_pids]
  end

  it "refuses the nested run, counts the mutant as killed and leaves nothing behind" do
    peak, tripped, leftover_pids = run_watched
    expect(tripped).to be_nil
    expect(peak).to be <= 4
    expect(leftover_pids).to be_empty

    report = JSON.parse(File.read(File.join(dir, ".saboteur", "report.json")))
    statuses = report.fetch("files").fetch("lib/gate.rb").fetch("mutants").map { |m| [m["replacement"], m["status"]] }
    # `>=` -> `<=` and `1` -> `0` open the gate for zero jobs, so the spec
    # calls Saboteur::CLI#call inside the mutant child.
    expect(statuses).to include(["<=", "Killed"], %w[0 Killed])
    expect(statuses.map(&:last)).not_to include("Timeout", "RuntimeError")
  end
end
