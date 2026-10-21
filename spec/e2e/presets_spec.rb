# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

RSpec.describe "saboteur pr / saboteur audit presets (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  def git(*args)
    _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
    raise err unless status.success?
  end

  it "pr runs the changed-lines loop against the given ref with one baseline check (#244)" do
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    path = File.join(dir, "lib", "people.rb")
    File.write(path, File.read(path).sub("@age}", "@age.to_s}"))

    run = saboteur(dir, "pr", "HEAD", "--all", "--verbose", command: nil)
    expect(run.err).to include("preset 'pr': --baseline-passes 1 --max-duration 10m --since HEAD")
    expect(run.err).to include("checking the unchanged suite once (seed 1)")
    expect(run.out).to include("4/4 mutants killed")
  end

  it "pr defaults the ref to main, says nothing to test, and exits 0 on an empty range (#659) (#244)" do
    git("init", "-q")
    git("checkout", "-q", "-b", "main")
    git("add", ".")
    git("commit", "-q", "-m", "base")

    run = saboteur(dir, "pr", "--all", command: nil)
    expect(run.status).to eq(0), run.err
    expect(run.err).to include("--since main: nothing to test - the resolved range has no changes")
  end

  it "audit runs the whole project and writes both reports (#244)" do
    run = saboteur(dir, "audit", command: nil)
    expect(run.err).to include("preset 'audit':")
    expect(run.status).to eq(1), run.err
    expect(File).to exist(File.join(dir, ".saboteur", "audit-report.json"))
    expect(File).to exist(File.join(dir, ".saboteur", "audit-report.html"))
  end
end
