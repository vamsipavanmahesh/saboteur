# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe Saboteur::WorkingTree do
  let(:root) { File.realpath(Dir.mktmpdir("saboteur-tree-")) }

  after { FileUtils.remove_entry(root) }

  def git(*args)
    Open3.capture2e("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: root)
  end

  def write(path, text = "x = 1\n")
    FileUtils.mkdir_p(File.dirname(File.join(root, path)))
    File.write(File.join(root, path), text)
  end

  def commit_one_file
    write("lib/a.rb")
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "first")
  end

  it "is unknown outside a git repository" do
    state = described_class.new(root).state
    expect(state).to eq(described_class::UNKNOWN)
    expect(state.label).to eq("unknown")
  end

  it "records the full SHA and a clean tree" do
    commit_one_file
    state = described_class.new(root).state
    expect(state.head).to eq(git("rev-parse", "HEAD").first.strip)
    expect([state.dirty, state.changed_files, state.label]).to eq([false, 0, "clean"])
  end

  it "counts a changed tracked file" do
    commit_one_file
    write("lib/a.rb", "x = 2\n")
    state = described_class.new(root).state
    expect([state.dirty, state.changed_files, state.label]).to eq([true, 1, "dirty"])
  end

  it "counts each untracked file, also inside new directories" do
    commit_one_file
    write("lib/new/b.rb")
    write("lib/new/deep/c.rb")
    expect(described_class.new(root).state.changed_files).to eq(2)
  end

  it "leaves out the ignored paths" do
    commit_one_file
    write(".saboteur/report.json", "{}")
    write("reports/out.html", "<html>")
    write("lib/new.rb")
    expect(described_class.new(root, ignored: [".saboteur", "reports/out.html"]).state.changed_files).to eq(1)
    expect(described_class.new(root).state.changed_files).to eq(3)
  end

  describe "changes" do
    it "lists each change with its path relative to the root and whether git tracks it" do
      commit_one_file
      write("lib/a.rb", "x = 2\n")
      write("notes/todo.md", "later")
      changes = described_class.new(root).state.changes

      expect(changes).to eq([described_class::Change.new(path: "lib/a.rb", tracked: true),
                             described_class::Change.new(path: "notes/todo.md", tracked: false)])
    end

    it "counts a rename once, under its new path, and a deletion under the deleted path" do
      commit_one_file
      write("lib/b.rb", "y = 1\n")
      git("add", ".")
      git("commit", "-q", "-m", "second")
      git("mv", "lib/a.rb", "lib/renamed.rb")
      File.delete(File.join(root, "lib/b.rb"))
      state = described_class.new(root).state

      expect(state.changes.map(&:path)).to eq(%w[lib/b.rb lib/renamed.rb])
      expect(state.changes.map(&:tracked)).to eq([true, true])
      expect(state.changed_files).to eq(2)
    end

    it "keeps paths with spaces, quotes and non-ASCII names as they are" do
      commit_one_file
      write("lib/a b.rb")
      write("lib/caf\u00e9.rb")
      write("lib/q\"uote.rb")

      expect(described_class.new(root).state.changes.map(&:path))
        .to contain_exactly("lib/a b.rb", "lib/caf\u00e9.rb", "lib/q\"uote.rb")
    end

    it "gives paths relative to a root below the top of the repository" do
      commit_one_file
      write("app/one/lib/x.rb")
      write("app/two/lib/y.rb")

      changes = described_class.new(File.join(root, "app/one")).state.changes
      expect(changes).to eq([described_class::Change.new(path: "lib/x.rb", tracked: false)])
    end
  end

  it "is unknown when git cannot read the head, or cannot read the status" do
    ok = ["abc\n\n", "", instance_double(Process::Status, success?: true)]
    bad = ["", "fatal\n", instance_double(Process::Status, success?: false)]
    allow(Open3).to receive(:capture3).and_return(bad, ok)
    expect(described_class.new(root).state).to eq(described_class::UNKNOWN)
    allow(Open3).to receive(:capture3).and_return(ok, bad)
    expect(described_class.new(root).state).to eq(described_class::UNKNOWN)
  end

  it "reads a status whose path is not valid UTF-8 without raising" do
    ok = ["abc\n\n", "", instance_double(Process::Status, success?: true)]
    bad_path = "lib/caf\xE9.rb".dup.force_encoding(Encoding::UTF_8)
    allow(Open3).to receive(:capture3).and_return(ok, ["?? #{bad_path}\0?? lib/b.rb\0", "", ok.last])
    expect(described_class.new(root).state.changes.map(&:path)).to eq([bad_path, "lib/b.rb"])
  end

  it "is unknown when git cannot be started" do
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)
    expect(described_class.new(root).state).to eq(described_class::UNKNOWN)
  end
end
