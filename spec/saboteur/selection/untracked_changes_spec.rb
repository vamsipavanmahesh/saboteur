# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Selection::UntrackedChanges do
  let(:diagnostics) { instance_double(Saboteur::Engine::Diagnostics, warn: nil) }

  describe ".warn_unreadable" do
    it "names up to five files, sorted, then an ellipsis" do
      described_class.warn_unreadable(%w[f.rb e.rb d.rb c.rb b.rb a.rb], diagnostics)
      expect(diagnostics).to have_received(:warn)
        .with("--since: 6 included untracked file(s) could not be read (vanished, unreadable or " \
              "replaced), so their subjects are not covered: a.rb, b.rb, c.rb, d.rb, e.rb, ...")
    end

    it "names every file when fewer are unreadable" do
      described_class.warn_unreadable(%w[c.rb a.rb b.rb], diagnostics)
      expect(diagnostics).to have_received(:warn)
        .with("--since: 3 included untracked file(s) could not be read (vanished, unreadable or " \
              "replaced), so their subjects are not covered: a.rb, b.rb, c.rb")
    end

    it "adds no ellipsis at exactly five" do
      described_class.warn_unreadable(%w[e.rb d.rb c.rb b.rb a.rb], diagnostics)
      expect(diagnostics).to have_received(:warn)
        .with("--since: 5 included untracked file(s) could not be read (vanished, unreadable or " \
              "replaced), so their subjects are not covered: a.rb, b.rb, c.rb, d.rb, e.rb")
    end

    it "stays quiet with nothing unreadable or no diagnostics" do
      described_class.warn_unreadable([], diagnostics)
      described_class.warn_unreadable(%w[a.rb], nil)
      expect(diagnostics).not_to have_received(:warn)
    end
  end

  describe ".line_count" do
    let(:flags) { File::RDONLY | File::NOFOLLOW | File::NONBLOCK }

    around do |example|
      Dir.mktmpdir { |dir| @dir = dir and example.run }
    end

    it "counts the lines of a regular file" do
      file = File.join(@dir, "a.rb")
      File.write(file, "1\n2\n3")
      expect(described_class.line_count(file, flags)).to eq(3)
    end

    it "is nil for an empty file and a binary file" do
      empty = File.join(@dir, "empty.rb")
      binary = File.join(@dir, "blob.rb")
      File.write(empty, "")
      File.binwrite(binary, "a\0b\n")
      expect(described_class.line_count(empty, flags)).to be_nil
      expect(described_class.line_count(binary, flags)).to be_nil
    end

    it "is :unreadable for a missing file, a symlink and a FIFO" do
      real = File.join(@dir, "real.rb")
      File.write(real, "1\n")
      File.symlink(real, File.join(@dir, "link.rb"))
      File.mkfifo(File.join(@dir, "pipe.rb"))
      expect(described_class.line_count(File.join(@dir, "gone.rb"), flags)).to eq(:unreadable)
      expect(described_class.line_count(File.join(@dir, "link.rb"), flags)).to eq(:unreadable)
      expect(described_class.line_count(File.join(@dir, "pipe.rb"), flags)).to eq(:unreadable)
    end
  end

  describe ".paths" do
    it "resolves a repository root whose path carries raw high bytes" do
      Dir.mktmpdir do |base|
        dir = File.join(base, "r\xC3\x28oot".b)
        begin
          Dir.mkdir(dir)
        rescue Errno::EILSEQ, Errno::EINVAL
          skip "this platform rejects paths that are not valid UTF-8"
        end
        git = lambda { |*args|
          Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
        }
        git.call("init", "-q")
        File.write(File.join(dir, "a.rb"), "1\n")
        git.call("add", ".")
        git.call("commit", "-q", "-m", "base")
        File.write(File.join(dir, "b.rb"), "1\n")

        paths = described_class.paths(dir)
        expect(paths.map { |path| File.basename(path) }).to eq(["b.rb"])
        expect(Saboteur::Selection::GitDiff.changed_lines("HEAD", root: dir).keys
                  .map { |path| File.basename(path) }).to eq(["b.rb"])
      end
    end
  end
end
