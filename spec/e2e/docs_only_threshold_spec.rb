# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

# A pull request that changes only documentation has no mutants and so no
# score. Gating it on --threshold must pass with a note, not fail a score of
# nothing (#1142, #1159).
RSpec.describe "saboteur run --since --threshold: a docs-only diff", :e2e do
  let(:dir) { copy_fixture("people") }

  def git(*args)
    _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
    raise err unless status.success?
  end

  before do
    File.write(File.join(dir, "NOTES.md"), "first draft\n")
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "base")
  end

  it "exits 0 with a no-mutants note when only a Markdown file changed" do
    File.write(File.join(dir, "NOTES.md"), "second draft\n")

    run = saboteur(dir, "--since", "HEAD", "--threshold", "90")

    expect(run.status).to eq(0), other_outcomes(run)
    expect(run.err).to include("no mutants in the diff")
  end

  it "exits 0 with the same note when the diff is empty" do
    run = saboteur(dir, "--since", "HEAD", "--threshold", "90")

    expect(run.status).to eq(0), other_outcomes(run)
    expect(run.err).to include("no mutants in the diff")
  end
end
