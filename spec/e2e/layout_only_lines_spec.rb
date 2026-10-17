# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "layout-only line changes in --since mode (issue #313)", :e2e do
  def commit(dir)
    system("git", "init", "-q", dir, exception: true)
    system("git", "-C", dir, "add", ".", exception: true)
    system("git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.com",
           "commit", "-q", "-m", "base", exception: true)
  end

  def wrap_in_lock(dir, body)
    lib = File.join(dir, "lib", "ledger.rb")
    File.write(lib, File.read(lib).sub(<<-OLD, body))
    @log << "recording \#{amount}"
    @entries << amount * 2
    OLD
  end

  # The whole-body mutants sit on the first body line, the new lock.
  def mutant_lines(run)
    mutants(run).map { |mutant| mutant.dig("location", "start", "line") }.uniq.sort
  end

  it "does not mutate statements that only moved into a new block" do
    dir = copy_fixture("wrapped")
    commit(dir)
    wrap_in_lock(dir, <<-NEW)
    Thread::Mutex.new.synchronize do
      @log << "recording \#{amount}"
      @entries << amount * 2
    end
    NEW

    run = saboteur(dir, "--since", "HEAD", "--agent")
    expect(mutant_lines(run)).to eq([13])
  end

  it "still mutates a re-indented statement that also changed" do
    dir = copy_fixture("wrapped")
    commit(dir)
    wrap_in_lock(dir, <<-NEW)
    Thread::Mutex.new.synchronize do
      @log << "recording \#{amount}"
      @entries << amount * 2 + 0
    end
    NEW

    run = saboteur(dir, "--since", "HEAD", "--agent")
    expect(mutant_lines(run)).to eq([13, 15])
  end
end
