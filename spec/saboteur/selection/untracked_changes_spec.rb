# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Selection::UntrackedChanges do
  let(:diagnostics) { instance_double(Saboteur::Engine::Diagnostics, warn: nil) }

  describe ".warn_unreadable" do
    it "names up to five files, sorted, then 'and N more'" do
      described_class.warn_unreadable(%w[f.rb e.rb d.rb c.rb b.rb a.rb], diagnostics)
      expect(diagnostics).to have_received(:warn)
        .with("--since: 6 included untracked file(s) could not be read (vanished, unreadable or " \
              "replaced), so their subjects are not covered: a.rb, b.rb, c.rb, d.rb, e.rb and 1 more")
    end

    it "counts every file past the fifth" do
      described_class.warn_unreadable(("a".."h").map { |name| "#{name}.rb" }, diagnostics)
      expect(diagnostics).to have_received(:warn)
        .with("--since: 8 included untracked file(s) could not be read (vanished, unreadable or " \
              "replaced), so their subjects are not covered: a.rb, b.rb, c.rb, d.rb, e.rb and 3 more")
    end

    it "names every file when fewer are unreadable" do
      described_class.warn_unreadable(%w[c.rb a.rb b.rb], diagnostics)
      expect(diagnostics).to have_received(:warn)
        .with("--since: 3 included untracked file(s) could not be read (vanished, unreadable or " \
              "replaced), so their subjects are not covered: a.rb, b.rb, c.rb")
    end

    it "adds no 'and N more' at exactly five" do
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

  describe ".union" do
    let(:diagnostics) { instance_double(Saboteur::Engine::Diagnostics, warn: nil, record_discovery_failure: nil) }

    def with_repo
      Dir.mktmpdir do |dir|
        dir = File.realpath(dir)
        git = lambda { |*args|
          out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com",
                                            *args, chdir: dir)
          raise err unless status.success?

          out
        }
        git.call("init", "-q")
        File.write(File.join(dir, "tracked.rb"), "1\n")
        git.call("add", ".")
        git.call("commit", "-q", "-m", "base")
        yield dir
      end
    end

    it "attempts and reports an included path swapped to a symlink outside the include set" do
      with_repo do |dir|
        Dir.mktmpdir do |outside|
          target = File.join(outside, "secret.rb")
          File.write(target, "1\n")
          File.symlink(target, File.join(dir, "swapped.rb"))

          changes = {}
          described_class.union(changes, dir, include: [File.join(dir, "swapped.rb")], diagnostics: diagnostics)

          expect(changes).to be_empty
          expect(diagnostics).to have_received(:warn)
            .with("--since: 1 included untracked file(s) could not be read (vanished, unreadable or " \
                  "replaced), so their subjects are not covered: swapped.rb")
          expect(diagnostics).to have_received(:record_discovery_failure)
            .with(File.join(dir, "swapped.rb"), reason: "unreadable")
        end
      end
    end

    it "keeps files in scope under a symlinked root whose include set is canonical" do
      with_repo do |dir|
        File.write(File.join(dir, "fresh.rb"), "1\n2\n")
        Dir.mktmpdir do |holder|
          link = File.join(holder, "link")
          File.symlink(dir, link)

          changes = {}
          described_class.union(changes, link, include: [File.join(dir, "fresh.rb")], diagnostics: diagnostics)

          expect(changes).to eq(File.join(link, "fresh.rb") => (1..2))
          expect(diagnostics).not_to have_received(:warn)
        end
      end
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
