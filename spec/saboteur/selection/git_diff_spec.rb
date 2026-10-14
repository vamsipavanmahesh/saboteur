# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe Saboteur::Selection::GitDiff do
  it "parses added, changed and deleted lines from a zero-context diff" do
    diff = <<~DIFF
      diff --git a/lib/a.rb b/lib/a.rb
      --- a/lib/a.rb
      +++ b/lib/a.rb
      @@ -3 +3 @@ class A
      -x
      +y
      @@ -10,2 +10,0 @@ class A
      -gone
      -gone
      @@ -20,0 +19,3 @@
      +n1
      +n2
      +n3
      diff --git a/old.rb b/old.rb
      --- a/old.rb
      +++ /dev/null
      @@ -1 +0,0 @@
      -bye
    DIFF
    expect(described_class.parse(diff, "/repo")).to eq("/repo/lib/a.rb" => Set[3, 10, 11, 19, 20, 21])
  end

  it "reads committed and uncommitted changes since a ref" do
    Dir.mktmpdir do |dir|
      git = lambda { |*args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
      }
      git.call("init", "-q")
      File.write(File.join(dir, "a.rb"), "1\n2\n3\n")
      git.call("add", ".")
      git.call("commit", "-q", "-m", "base")
      git.call("tag", "base")
      File.write(File.join(dir, "a.rb"), "1\nTWO\n3\n4\n")
      changed = described_class.changed_lines("base", root: dir)
      expect(changed.transform_keys { |k| File.basename(k) }).to eq("a.rb" => Set[2, 4])
    end
  end

  it "finds changed files whose names git would quote: spaces, non-ASCII, quotes" do
    Dir.mktmpdir do |dir|
      git = lambda { |*args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
      }
      names = ["my file.rb", "h\u00e9llo.rb", "say \"hi\".rb"]
      git.call("init", "-q")
      names.each { |name| File.write(File.join(dir, name), "1\n") }
      git.call("add", ".")
      git.call("commit", "-q", "-m", "base")
      names.each { |name| File.write(File.join(dir, name), "2\n") }
      changed = described_class.changed_lines("HEAD", root: dir)
      expect(changed.keys.map { |path| path.delete_prefix("#{File.realpath(dir)}/") }.sort)
        .to eq(names.sort)
      expect(changed["#{File.realpath(dir)}/nope.rb"]).to be_nil
    end
  end

  describe ".unquote" do
    it "decodes git's C quoting: octal bytes and named escapes" do
      expect(described_class.unquote('"b/h\\303\\251llo.rb"')).to eq("b/h\u00e9llo.rb")
      expect(described_class.unquote('"b/a\\tb\\"c.rb"')).to eq("b/a\tb\"c.rb")
      expect(described_class.unquote("b/plain.rb")).to eq("b/plain.rb")
    end
  end

  it "raises a usage error for an unknown ref" do
    Dir.mktmpdir do |dir|
      Open3.capture3("git", "init", "-q", chdir: dir)
      expect { described_class.changed_lines("nope", root: dir) }.to raise_error(Saboteur::ConfigError, /--since nope/)
    end
  end

  describe "against a repository" do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    def git(*args)
      Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @dir)
    end

    def commit_file(name, text)
      File.write(File.join(@dir, name), text)
      git("add", ".")
      git("commit", "-q", "-m", name)
    end

    before { git("init", "-q") }

    describe ".verify_ref!" do
      it "accepts a commit, a branch and a tag" do
        commit_file("a.rb", "1\n")
        git("tag", "v1")

        %w[HEAD v1].push(git("branch", "--show-current").first.strip).each do |ref|
          expect { described_class.verify_ref!(ref, root: @dir) }.not_to raise_error
        end
      end

      it "refuses an unknown ref as a usage error that names the ref" do
        commit_file("a.rb", "1\n")

        expect { described_class.verify_ref!("no-such-ref", root: @dir) }
          .to raise_error(Saboteur::ConfigError, /--since no-such-ref: not a commit in this repository/)
      end

      it "refuses a name that is a blob, not a commit" do
        commit_file("a.rb", "1\n")

        expect { described_class.verify_ref!("HEAD:a.rb", root: @dir) }.to raise_error(Saboteur::ConfigError)
      end

      it "refuses a ref that looks like an option" do
        expect { described_class.verify_ref!("--output=x", root: @dir) }
          .to raise_error(Saboteur::ConfigError, /needs a git ref, not an option: --output=x/)
      end
    end

    it "says --since needs a git repository outside one" do
      Dir.mktmpdir do |plain|
        expect { described_class.verify_ref!("HEAD", root: plain) }
          .to raise_error(Saboteur::ConfigError, "--since needs a git repository")
      end
    end

    describe ".file_at" do
      it "reads the file as it was at the base, relative to root" do
        FileUtils.mkdir_p(File.join(@dir, "lib"))
        commit_file("lib/a.rb", "old\n")
        base = described_class.merge_base("HEAD", root: @dir)
        File.write(File.join(@dir, "lib", "a.rb"), "new\n")

        expect(described_class.file_at(base, "lib/a.rb", root: @dir)).to eq("old\n")
        expect(described_class.file_at(base, "lib/new.rb", root: @dir)).to be_nil
      end
    end
  end
  it "marks only the changed lines, not their context, in a long file" do
    Dir.mktmpdir do |dir|
      git = lambda { |*args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
      }
      git.call("init", "-q")
      File.write(File.join(dir, "a.rb"), (1..10).map { |n| "line#{n}\n" }.join)
      git.call("add", ".")
      git.call("commit", "-q", "-m", "base")
      git.call("tag", "base")
      File.write(File.join(dir, "a.rb"), (1..10).map { |n| n == 5 ? "CHANGED\n" : "line#{n}\n" }.join)
      changed = described_class.changed_lines("base", root: dir)
      expect(changed.transform_keys { |k| File.basename(k) }).to eq("a.rb" => Set[5])
    end
  end

  it "parses the diff when git is configured to always colorize" do
    Dir.mktmpdir do |dir|
      git = lambda { |*args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
      }
      git.call("init", "-q")
      git.call("config", "color.ui", "always")
      File.write(File.join(dir, "a.rb"), "1\n2\n")
      git.call("add", ".")
      git.call("commit", "-q", "-m", "base")
      git.call("tag", "base")
      File.write(File.join(dir, "a.rb"), "1\nTWO\n")
      changed = described_class.changed_lines("base", root: dir)
      expect(changed.transform_keys { |k| File.basename(k) }).to eq("a.rb" => Set[2])
    end
  end

  it "ignores a configured external diff tool" do
    Dir.mktmpdir do |dir|
      git = lambda { |*args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
      }
      git.call("init", "-q")
      script = File.join(dir, "fake-diff")
      File.write(script, "#!/bin/sh\necho GARBAGE\n")
      File.chmod(0o755, script)
      git.call("config", "diff.external", script)
      File.write(File.join(dir, "a.rb"), "1\n2\n")
      git.call("add", ".")
      git.call("commit", "-q", "-m", "base")
      git.call("tag", "base")
      File.write(File.join(dir, "a.rb"), "1\nTWO\n")
      changed = described_class.changed_lines("base", root: dir)
      expect(changed.transform_keys { |k| File.basename(k) }).to eq("a.rb" => Set[2])
    end
  end

  it "separates the base rev from pathspecs when a file is named like it" do
    Dir.mktmpdir do |dir|
      git = lambda { |*args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
      }
      git.call("init", "-q")
      File.write(File.join(dir, "a.rb"), "1\n")
      git.call("add", ".")
      git.call("commit", "-q", "-m", "base")
      git.call("tag", "base")
      sha = git.call("merge-base", "base", "HEAD").first.strip
      File.write(File.join(dir, sha), "x\n")
      File.write(File.join(dir, "a.rb"), "1\n2\n")
      changed = described_class.changed_lines("base", root: dir)
      expect(changed.transform_keys { |k| File.basename(k) }).to eq("a.rb" => Set[2])
    end
  end
  it "compares against the merge base, not the index, so committed changes count" do
    Dir.mktmpdir do |dir|
      git = lambda { |*args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
      }
      git.call("init", "-q")
      File.write(File.join(dir, "a.rb"), "1\n")
      git.call("add", ".")
      git.call("commit", "-q", "-m", "base")
      git.call("tag", "base")
      File.write(File.join(dir, "a.rb"), "1\n2\n")
      git.call("add", ".")
      git.call("commit", "-q", "-m", "change")
      changed = described_class.changed_lines("base", root: dir)
      expect(changed.transform_keys { |k| File.basename(k) }).to eq("a.rb" => Set[2])
    end
  end
end
