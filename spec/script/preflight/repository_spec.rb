# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe Preflight::Repository, :fixture do
  let(:base) { @base }

  it "verifies an exact, clean checkout (valid control)" do
    @fixture.write("a.txt", "a\n")
    @fixture.commit("change")
    repository = @fixture.repository(base: base)
    expect([repository.merge_base, repository.changes.map(&:path)]).to eq([base, ["a.txt"]])
  end

  it "rejects a dirty tree, including untracked files" do
    @fixture.write("a.txt", "a\n")
    @fixture.commit("change")
    @fixture.write("stray.rb", "x\n")
    expect { @fixture.repository(base: base) }.to raise_error(Preflight::UnverifiableInput, /not clean/)
  end

  it "does not count the harness output directory as a dirty tree" do
    @fixture.write("a.txt", "a\n")
    @fixture.commit("change")
    @fixture.write("tmp/preflight/run/report.json", "{}")
    expect { @fixture.repository(base: base) }.not_to raise_error
  end

  it "rejects a checkout whose HEAD is not --head" do
    @fixture.write("a.txt", "a\n")
    @fixture.commit("change")
    options = @fixture.options(base: base)
    options.head = base
    repository = described_class.new(command_runner: @fixture.runner, options: options, directory: @fixture.directory)
    expect { repository.verify_identity! }.to raise_error(Preflight::UnverifiableInput, /not --head/)
  end

  it "rejects a commit that is not available locally" do
    options = @fixture.options(base: "0" * 40)
    repository = described_class.new(command_runner: @fixture.runner, options: options, directory: @fixture.directory)
    expect { repository.verify_identity! }.to raise_error(Preflight::UnverifiableInput, /not available/)
  end

  it "lists hostile file names exactly and shows renames as a delete plus an add" do
    @fixture.write("old name.txt", "same\n")
    @fixture.commit("add")
    new_base = @fixture.head
    @fixture.git("mv", "old name.txt", "new\nline $(x).txt")
    @fixture.commit("rename")
    changes = @fixture.repository(base: new_base).changes
    expect(changes.map do |c|
      [c.status, c.path]
    end).to contain_exactly(["D", "old name.txt"], ["A", "new\nline $(x).txt"])
  end

  it "reports a symlink change with its mode" do
    @fixture.write("target.txt", "t\n")
    File.symlink("target.txt", File.join(@fixture.directory, "link"))
    @fixture.commit("link")
    modes = @fixture.repository(base: base).changes.map(&:new_mode)
    expect(modes).to include(Preflight::Repository::SYMLINK_MODE)
  end

  it "refuses files marked assume-unchanged, which hide edits from git status" do
    @fixture.git("update-index", "--assume-unchanged", "README.md")
    @fixture.write("README.md", "hidden edit\n")
    expect { @fixture.repository(base: base) }.to raise_error(Preflight::UnverifiableInput, /assume-unchanged/)
  end

  it "refuses files marked skip-worktree" do
    @fixture.git("update-index", "--skip-worktree", "README.md")
    @fixture.write("README.md", "hidden edit\n")
    expect { @fixture.repository(base: base) }.to raise_error(Preflight::UnverifiableInput, /skip-worktree/)
  end

  it "still sees a dirty source file when the harness output directory exists" do
    @fixture.write("tmp/preflight/run/report.json", "{}")
    @fixture.write("README.md", "edited\n")
    expect { @fixture.repository(base: base) }.to raise_error(Preflight::UnverifiableInput, /not clean/)
  end

  it "refuses an output root that is a symlink to another place" do
    FileUtils.mkdir_p(File.join(@fixture.directory, "tmp"))
    File.symlink(File.join(@fixture.directory, "README.md"), File.join(@fixture.directory, "tmp/preflight"))
    expect { @fixture.repository(base: base) }.to raise_error(Preflight::UnverifiableInput, /symlink/)
  end

  it "refuses tracked files under the output root, which status would ignore" do
    @fixture.write("tmp/preflight/tracked.rb", "x\n")
    @fixture.git("add", "-f", "tmp/preflight/tracked.rb")
    @fixture.commit("track output")
    expect { @fixture.repository(base: base) }.to raise_error(Preflight::UnverifiableInput, /tracked files exist/)
  end

  it "reports no origin/main snapshot when the checkout has none" do
    expect(@fixture.repository(base: base).origin_main_snapshot).to be_nil
  end
end
