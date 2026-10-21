# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "docs-only diff under a threshold (B3)", :e2e do
  def committed_fixture(name)
    dir = copy_fixture(name)
    system("git", "init", "-q", dir, exception: true)
    system("git", "-C", dir, "add", ".", exception: true)
    system("git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.com",
           "commit", "-q", "-m", "base", exception: true)
    dir
  end

  def docs_only_commit(dir)
    File.write(File.join(dir, "README.md"), "# docs only\n")
  end

  it "exits 0 with the threshold notice for a docs-only --since diff under --threshold" do
    dir = committed_fixture("people")
    docs_only_commit(dir)
    run = saboteur(dir, "--since", "HEAD", "--threshold", "80")
    expect(run.status).to eq(0), run.err
    expect(run.err).to include("saboteur: no mutants in the diff - nothing to gate (threshold 80 skipped)")
    expect(run.out).not_to include("gate limits exceeded")
  end

  it "keeps the plain notice for a docs-only --since diff without a threshold" do
    dir = committed_fixture("people")
    docs_only_commit(dir)
    run = saboteur(dir, "--since", "HEAD")
    expect(run.status).to eq(0), run.err
    expect(run.err).to include("saboteur: no mutants in the diff - nothing to gate\n")
  end

  it "still gates a diff that changes code: the threshold decides the exit" do
    dir = committed_fixture("people")
    source = File.join(dir, "lib", "people.rb")
    File.write(source, File.read(source).sub("@age >= 18", "@age > 18"))
    below = saboteur(dir, "--since", "HEAD", "--threshold", "100")
    expect(below.status).to eq(1), below.err
    expect(below.err).not_to include("no mutants in the diff")
    above = saboteur(dir, "--since", "HEAD", "--threshold", "0")
    expect(above.status).to eq(0), above.err
  end
end
