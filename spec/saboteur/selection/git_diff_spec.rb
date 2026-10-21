# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "timeout"
require "stringio"
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
      expect(described_class.unquote('"b/a\\q.rb"')).to eq("b/aq.rb")
    end
  end

  describe ".deletion_only_files" do
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

    # core.quotePath=false writes the raw name bytes into the diff: the
    # parser must read them as bytes, not as UTF-8 (#549).
    it "detects a deletion-only file whose name is not valid UTF-8" do
      name = "del_\xFF.rb".b
      begin
        File.write(File.join(@dir, name), "x\ny\n")
      rescue Errno::EILSEQ, Errno::EINVAL
        skip "this platform rejects filenames that are not valid UTF-8"
      end
      git("add", ".")
      git("commit", "-q", "-m", "add")
      File.write(File.join(@dir, name), "x\n")
      result = described_class.deletion_only_files("HEAD", root: @dir)
      expect(result.map(&:b)).to eq([File.join(File.realpath(@dir), name)])
    end

    # Open3 output takes the locale encoding; under LC_ALL=C a non-ASCII
    # toplevel is US-ASCII-tagged with high bytes, and a plain strip raises
    # Encoding::CompatibilityError. The toplevel must be stripped as bytes.
    it "strips a locale-tagged non-ASCII toplevel without raising" do
      commit_file("a.rb", "x\ny\n")
      File.write(File.join(@dir, "a.rb"), "x\n")
      top = "#{File.realpath(@dir)}/pr\xC3\xA9x\n".force_encoding(Encoding::US_ASCII)
      FileUtils.mkdir_p(top.b.strip)
      allow(described_class).to receive(:git).and_call_original
      allow(described_class).to receive(:git).with(@dir, "rev-parse", "--show-toplevel").and_return(top)
      expect { described_class.deletion_only_files("HEAD", root: @dir) }.not_to raise_error
    end

    it "diffs against the merge base with the exact argv" do
      commit_file("a.rb", "x\ny\n")
      File.write(File.join(@dir, "a.rb"), "x\n")
      allow(described_class).to receive(:git).and_call_original
      base = described_class.merge_base("HEAD", root: @dir)
      expect(described_class.deletion_only_files("HEAD", root: @dir))
        .to eq([File.join(File.realpath(@dir), "a.rb")])
      expect(described_class).to have_received(:git)
        .with(@dir, "-c", "core.quotePath=false", "diff", "--unified=0", "--no-color", "--no-ext-diff", base, "--")
    end

    # added[file] ||= ... keeps a file with ANY adding hunk out of the
    # list; plain = would let a trailing delete-only hunk flip it (#549).
    it "does not list a file whose earlier hunk adds lines when a later hunk only deletes" do
      commit_file("a.rb", "a\nb\nc\n")
      File.write(File.join(@dir, "a.rb"), "x\na\nb\n")
      expect(described_class.deletion_only_files("HEAD", root: @dir)).to eq([])
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

      it "names the repo's default branch when origin publishes one (#595)" do
        commit_file("a.rb", "1\n")
        sha = git("rev-parse", "HEAD").first.strip
        git("update-ref", "refs/remotes/origin/master", sha)
        git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/master")

        # A ref that cannot exist on any host: git init.defaultBranch varies
        # ("main" on Vamsi's Mac), so the unresolvable name must not be a
        # plausible branch name (#709 macOS red).
        expect { described_class.verify_ref!("no-such-ref", root: @dir) }
          .to raise_error(Saboteur::ConfigError) { |error|
            expect(error.message).to eq("--since no-such-ref: not a commit in this repository " \
                                        "(check the name; a shallow checkout may need a deeper fetch); " \
                                        "this repository's default branch is 'master' - " \
                                        "pass it explicitly: saboteur pr master")
          }
      end

      it "lists the local branches when origin publishes no default branch (#595, #1225)" do
        commit_file("a.rb", "1\n")
        git("branch", "-m", "feature")
        git("branch", "master")
        git("branch", "main")
        git("branch", "aaa")

        expect { described_class.verify_ref!("no-such-ref", root: @dir) }
          .to raise_error(Saboteur::ConfigError) { |error|
            expect(error.message).to eq("--since no-such-ref: not a commit in this repository " \
                                        "(check the name; a shallow checkout may need a deeper fetch); " \
                                        "local branches: main, master, aaa, feature - " \
                                        "pass one explicitly: saboteur pr main")
          }
      end

      it "orders base names first, then the rest alphabetically" do
        expect(described_class.likely_bases(%w[zeta alpha develop master beta main trunk]))
          .to eq(%w[main master trunk develop alpha beta zeta])
      end

      it "caps the local branch list and keeps the plain hint when there is no branch" do
        expect { described_class.verify_ref!("no-such-ref", root: @dir) }
          .to raise_error(Saboteur::ConfigError) { |error|
            expect(error.message).to eq("--since no-such-ref: not a commit in this repository " \
                                        "(check the name; a shallow checkout may need a deeper fetch)")
          }
        commit_file("a.rb", "1\n")
        %w[b1 b2 b3 b4 b5 b6 b7].each { |name| git("branch", name) }

        expect { described_class.verify_ref!("no-such-ref", root: @dir) }
          .to raise_error(Saboteur::ConfigError) { |error|
            expect(error.message.split("local branches: ").last.split(" - ").first.split(", ").size).to eq(5)
          }
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

    describe ".line_maps behavior lines without layout-only edits (#313)" do
      def changed_after(before, after)
        commit_file("a.rb", before)
        File.write(File.join(@dir, "a.rb"), after)
        described_class.line_maps("HEAD", root: @dir).behavior.fetch(File.join(File.realpath(@dir), "a.rb"), Set.new)
      end

      # Open3 output takes the locale encoding; under LC_ALL=C a non-ASCII
      # toplevel is US-ASCII-tagged with high bytes and a plain strip raises.
      it "strips a locale-tagged non-ASCII toplevel without raising" do
        commit_file("a.rb", "x\ny\n")
        File.write(File.join(@dir, "a.rb"), "x\nz\n")
        top = "#{File.realpath(@dir)}/pr\xC3\xA9x\n".force_encoding(Encoding::US_ASCII)
        FileUtils.mkdir_p(top.b.strip)
        allow(described_class).to receive(:git).and_call_original
        allow(described_class).to receive(:git).with(@dir, "rev-parse", "--show-toplevel").and_return(top)
        expect { described_class.line_maps("HEAD", root: @dir) }.not_to raise_error
      end

      it "keeps every touched line in the changed map, for subject selection" do
        commit_file("a.rb", "def a\n  one\nend\n")
        File.write(File.join(@dir, "a.rb"), "def a\n    one\nend\n")
        maps = described_class.line_maps("HEAD", root: @dir)
        file = File.join(File.realpath(@dir), "a.rb")

        expect(maps.changed.fetch(file)).to eq(Set[2])
        expect(maps.behavior.fetch(file)).to eq(Set[])
        expect(described_class.changed_lines("HEAD", root: @dir).fetch(file)).to eq(Set[2])
      end

      it "keeps only the new lines when existing statements are wrapped in a block" do
        before = <<~RUBY
          def save
            log("saving")
            write
          end
        RUBY
        after = <<~RUBY
          def save
            lock.synchronize do
              log("saving")
              write
            end
          end
        RUBY

        expect(changed_after(before, after)).to eq(Set[2, 5])
      end

      it "keeps a re-indented line whose expression also changed" do
        before = "def save\n  write(1)\n  log\nend\n"
        after = "def save\n  lock.synchronize do\n    write(2)\n    log\n  end\nend\n"

        expect(changed_after(before, after)).to eq(Set[2, 3, 5])
      end

      it "drops a line where only the spacing between tokens changed" do
        expect(changed_after("x = a + b\ny = 1\n", "x = a   +  b\ny = 2\n")).to eq(Set[2])
      end

      it "drops a line whose only change is its trailing note, but keeps one that gains a directive (#892)" do
        expect(changed_after("x = 1\ny = 1\n", "x = 1 # note\ny = 2\n")).to eq(Set[2])
        expect(changed_after("x = 1\n", "x = 1 # saboteur:disable-line reason=\"known\"\n")).to eq(Set[1])
      end

      it "keeps a line where whitespace inside a string changed" do
        expect(changed_after("log(\"a b\")\n", "log(\"a  b\")\n")).to eq(Set[1])
      end

      it "keeps a line whose __LINE__ now names another line" do
        before = "def at\n  __LINE__\nend\n"
        after = "def at\n  begin\n    __LINE__\n  end\nend\n"

        expect(changed_after(before, after)).to eq(Set[2, 3, 4])
      end

      it "keeps the old coordinates of a pure deletion beside a re-indented line" do
        before = "def a\n  one\n  two\n  three\nend\n"
        after = "def a\n    one\n  three\nend\n"

        expect(changed_after(before, after)).to eq(Set[2, 3])
      end

      it "keeps a re-indented line inside a multi-line string, whose content changed" do
        expect(changed_after("x = \"a\n  b\"\n", "x = \"a\n    b\"\n")).to eq(Set[2])
      end

      it "drops a re-indented __LINE__ that stayed on its line" do
        expect(changed_after("def at\n  __LINE__\nend\n", "def at\n    __LINE__\nend\n")).to eq(Set[])
      end

      it "drops a re-indented last line when lines follow it now" do
        expect(changed_after("  a\n", "    a\nb\n")).to eq(Set[2])
      end

      it "keeps a line where space now separates tokens that touched" do
        expect(changed_after("x = a+b\n", "x = a + b\n")).to eq(Set[1])
      end

      it "keeps every changed line of a file outside the include set, unread" do
        commit_file("a.rb", "def a\n  one\nend\n")
        File.write(File.join(@dir, "a.rb"), "def a\n    one\nend\n")
        file = File.join(File.realpath(@dir), "a.rb")

        expect(described_class.line_maps("HEAD", root: @dir,
                                                 include: Set["/elsewhere.rb"]).behavior.fetch(file)).to eq(Set[2])
        expect(described_class.line_maps("HEAD", root: @dir, include: Set[file]).behavior.fetch(file)).to eq(Set[])
      end

      it "keeps every line of a file committed after the base" do
        commit_file("a.rb", "a = 1\n")
        base = git("rev-parse", "HEAD").first.strip
        commit_file("b.rb", "  b = 1\n  c = 2\n")
        changed = described_class.line_maps(base, root: @dir).behavior

        expect(changed.fetch(File.join(File.realpath(@dir), "b.rb"))).to eq(Set[1, 2])
      end

      it "drops re-indented lines in a file whose name holds a space" do
        commit_file("a b.rb", "def a\n  one\nend\n")
        File.write(File.join(@dir, "a b.rb"), "def a\n    one\nend\n")

        expect(described_class.line_maps("HEAD", root: @dir).behavior.fetch(File.join(File.realpath(@dir), "a b.rb")))
          .to eq(Set[])
      end

      it "maps lines against the base, not the index, when the change is staged" do
        commit_file("a.rb", "a\n  b\n")
        File.write(File.join(@dir, "a.rb"), "new\na\n    b\n")
        git("add", "a.rb")

        expect(described_class.line_maps("HEAD", root: @dir).behavior.fetch(File.join(File.realpath(@dir), "a.rb")))
          .to eq(Set[1])
      end

      it "drops a blank line that lost its spaces, and holds no token now" do
        expect(changed_after("a = 1\n  \nb = 2\n", "a = 1\n\nb = 2\n")).to eq(Set[])
      end

      it "drops a blank line that only gained spaces" do
        expect(changed_after("a = 1\n\nb = 2\n", "a = 1\n  \nb = 2\n")).to eq(Set[])
      end

      it "keeps a re-indented heredoc body line, since heredoc text is a token" do
        expect(changed_after("x = <<~T\n  a\nT\n", "x = <<~T\n    a\nT\n")).to eq(Set[2])
      end

      it "leaves an untracked file fully changed" do
        commit_file("b.rb", "b = 1\n")
        File.write(File.join(@dir, "c.rb"), "  c = 1\n")
        changed = described_class.line_maps("HEAD", root: @dir).behavior

        expect(changed.fetch(File.join(File.realpath(@dir), "c.rb"))).to eq(1..1)
      end
    end

    describe ".changed_lines with untracked files (#295)" do
      it "treats every line of an untracked file as changed" do
        commit_file("a.rb", "1\n")
        File.write(File.join(@dir, "new.rb"), "1\n2\n3\n")
        changed = described_class.changed_lines("HEAD", root: @dir)
        expect(changed.transform_keys { |path| File.basename(path) }).to eq("new.rb" => (1..3))
      end

      it "counts a final line without a trailing newline" do
        commit_file("a.rb", "1\n")
        File.write(File.join(@dir, "new.rb"), "1\n2")
        changed = described_class.changed_lines("HEAD", root: @dir)
        expect(changed.transform_keys { |path| File.basename(path) }).to eq("new.rb" => (1..2))
      end

      it "reads untracked files whose names are not valid UTF-8" do
        commit_file("a.rb", "1\n")
        name = "h\xE9llo.rb".b
        begin
          File.binwrite(File.join(@dir, name), "1\n2\n")
        rescue Errno::EILSEQ, Errno::EINVAL
          skip "this platform rejects filenames that are not valid UTF-8"
        end
        changed = described_class.changed_lines("HEAD", root: @dir)
        expect(changed.transform_keys { |path| File.basename(path) }).to eq(
          name.dup.force_encoding(Encoding::UTF_8) => (1..2)
        )
      end

      it "skips untracked symlinks instead of reading through them" do
        commit_file("a.rb", "1\n")
        File.write(File.join(@dir, "real.rb"), "1\n")
        File.symlink(File.join(@dir, "real.rb"), File.join(@dir, "link.rb"))
        changed = described_class.changed_lines("HEAD", root: @dir)
        expect(changed.keys.map { |path| File.basename(path) }).to eq(["real.rb"])
      end

      it "does not follow a symlink swapped in after the listing" do
        commit_file("a.rb", "1\n")
        File.write(File.join(@dir, "real.rb"), "1\n")
        File.symlink(File.join(@dir, "real.rb"), File.join(@dir, "link.rb"))
        allow(described_class).to receive(:git).and_call_original
        allow(described_class).to receive(:git)
          .with(File.realpath(@dir), "ls-files", "-z", "--others", "--exclude-standard").and_return("link.rb\0")
        changed = described_class.changed_lines("HEAD", root: @dir)
        expect(changed.keys.map { |path| File.basename(path) }).to eq([])
      end

      it "does not hang on a FIFO swapped in after the listing" do
        commit_file("a.rb", "1\n")
        File.mkfifo(File.join(@dir, "pipe.rb"))
        allow(described_class).to receive(:git).and_call_original
        allow(described_class).to receive(:git)
          .with(File.realpath(@dir), "ls-files", "-z", "--others", "--exclude-standard").and_return("pipe.rb\0")
        Timeout.timeout(3) do
          expect(described_class.changed_lines("HEAD", root: @dir)).to eq({})
        end
      end

      it "skips a file that vanishes after the listing" do
        commit_file("a.rb", "1\n")
        allow(described_class).to receive(:git).and_call_original
        allow(described_class).to receive(:git)
          .with(File.realpath(@dir), "ls-files", "-z", "--others", "--exclude-standard").and_return("gone.rb\0")
        expect(described_class.changed_lines("HEAD", root: @dir)).to eq({})
      end

      it "skips an unreadable file after the listing" do
        commit_file("a.rb", "1\n")
        File.write(File.join(@dir, "secret.rb"), "1\n")
        File.chmod(0o000, File.join(@dir, "secret.rb"))
        changed = described_class.changed_lines("HEAD", root: @dir)
        expect(changed.keys.map { |path| File.basename(path) }).to eq([])
      end

      it "never opens untracked files outside the include set" do
        commit_file("a.rb", "1\n")
        big = File.join(@dir, "big.bin")
        File.open(big, "w") { |io| io.truncate(50 * 1024 * 1024) }
        File.write(File.join(@dir, "new.rb"), "1\n")
        allow(File).to receive(:open).and_call_original
        include = [File.realpath(File.join(@dir, "a.rb"))].to_set
        changed = described_class.changed_lines("HEAD", root: @dir, include: include)
        expect(changed).to eq({})
        expect(File).not_to have_received(:open).with(/big\.bin/, any_args)
        expect(File).not_to have_received(:open).with(/new\.rb/, any_args)
      end

      it "marks a many-line untracked file with a range, not a Set" do
        commit_file("a.rb", "1\n")
        File.write(File.join(@dir, "big.rb"), "# c\n" * 200_000)
        changed = described_class.changed_lines("HEAD", root: @dir)
        value = changed.fetch(changed.keys.find { |path| path.end_with?("big.rb") })
        expect(value).to be_a(Range)
        expect(value).to eq(1..200_000)
      end

      it "warns and skips the union where safe open flags are unavailable" do
        commit_file("a.rb", "1\n")
        File.write(File.join(@dir, "new.rb"), "1\n")
        diagnostics = instance_double(Saboteur::Engine::Diagnostics)
        allow(diagnostics).to receive(:warn)
        allow(File).to receive(:const_defined?).and_call_original
        allow(File).to receive(:const_defined?).with(:NOFOLLOW).and_return(false)
        changed = described_class.changed_lines("HEAD", root: @dir, diagnostics: diagnostics)
        expect(changed).to eq({})
        expect(diagnostics).to have_received(:warn).with(/untracked files are not included.*race-free/)
      end

      it "warns and skips the union when only O_NONBLOCK is unavailable" do
        commit_file("a.rb", "1\n")
        File.write(File.join(@dir, "new.rb"), "1\n")
        diagnostics = instance_double(Saboteur::Engine::Diagnostics)
        allow(diagnostics).to receive(:warn)
        allow(File).to receive(:const_defined?).and_call_original
        allow(File).to receive(:const_defined?).with(:NONBLOCK).and_return(false)
        changed = described_class.changed_lines("HEAD", root: @dir, diagnostics: diagnostics)
        expect(changed).to eq({})
        expect(diagnostics).to have_received(:warn).with(/untracked files are not included.*race-free/)
      end

      it "skips the union quietly when flags are unavailable and no diagnostics are given" do
        commit_file("a.rb", "1\n")
        File.write(File.join(@dir, "new.rb"), "1\n")
        allow(File).to receive(:const_defined?).and_call_original
        allow(File).to receive(:const_defined?).with(:NOFOLLOW).and_return(false)
        expect { described_class.changed_lines("HEAD", root: @dir) }.not_to raise_error
      end

      it "skips a FIFO even when a writer has data ready" do
        commit_file("a.rb", "1\n")
        path = File.join(@dir, "pipe.rb")
        File.mkfifo(path)
        reader = File.open(path, File::RDONLY | File::NONBLOCK) # rubocop:disable Style/FileOpen -- closed in ensure
        writer = Thread.new do
          File.open(path, File::WRONLY) do |io|
            io.write("1\n2\n")
            sleep 1
          end
        rescue SystemCallError, IOError
          nil
        end
        sleep 0.1
        allow(described_class).to receive(:git).and_call_original
        allow(described_class).to receive(:git)
          .with(File.realpath(@dir), "ls-files", "-z", "--others", "--exclude-standard").and_return("pipe.rb\0")
        expect(described_class.changed_lines("HEAD", root: @dir)).to eq({})
      ensure
        reader&.close
        writer&.join(3)&.kill
      end

      it "counts a multi-chunk file without a trailing newline exactly" do
        commit_file("a.rb", "1\n")
        File.write(File.join(@dir, "big.rb"), "#{"# c\n" * 100_000}# tail")
        changed = described_class.changed_lines("HEAD", root: @dir)
        value = changed.fetch(changed.keys.find { |path| path.end_with?("big.rb") })
        expect(value).to eq(1..100_001)
      end

      it "bounds every read while counting lines" do
        untracked = Saboteur::Selection::UntrackedChanges
        io = StringIO.new("1\n2\n")
        allow(io).to receive(:read).with(untracked::BINARY_SNIFF_BYTES).and_call_original
        allow(io).to receive(:read).with(untracked::READ_CHUNK_BYTES).and_return(nil)
        expect(untracked.count_lines(io)).to eq(2)
        expect(io).to have_received(:read).with(untracked::BINARY_SNIFF_BYTES)
      end

      it "warns when an included untracked file vanishes before the read" do
        commit_file("a.rb", "1\n")
        path = File.join(@dir, "gone.rb")
        File.write(path, "1\n")
        include = [File.realpath(path)].to_set
        File.delete(path)
        diagnostics = instance_double(Saboteur::Engine::Diagnostics)
        allow(diagnostics).to receive(:warn)
        allow(diagnostics).to receive(:record_discovery_failure)
        allow(described_class).to receive(:git).and_call_original
        allow(described_class).to receive(:git)
          .with(File.realpath(@dir), "ls-files", "-z", "--others", "--exclude-standard").and_return("gone.rb\0")
        changed = described_class.changed_lines("HEAD", root: @dir, include: include, diagnostics: diagnostics)
        expect(changed).to eq({})
        expect(diagnostics).to have_received(:warn).with(/included untracked file.*gone\.rb/m)
        expect(diagnostics).to have_received(:record_discovery_failure)
          .with(File.join(File.realpath(@dir), "gone.rb"), reason: "unreadable")
      end

      it "warns when an included untracked file cannot be read" do
        commit_file("a.rb", "1\n")
        File.write(File.join(@dir, "secret.rb"), "1\n")
        File.chmod(0o000, File.join(@dir, "secret.rb"))
        include = [File.realpath(File.join(@dir, "secret.rb"))].to_set
        diagnostics = instance_double(Saboteur::Engine::Diagnostics)
        allow(diagnostics).to receive(:warn)
        allow(diagnostics).to receive(:record_discovery_failure)
        changed = described_class.changed_lines("HEAD", root: @dir, include: include, diagnostics: diagnostics)
        expect(changed).to eq({})
        expect(diagnostics).to have_received(:warn).with(/included untracked file.*secret\.rb/m)
        expect(diagnostics).to have_received(:record_discovery_failure)
          .with(File.join(File.realpath(@dir), "secret.rb"), reason: "unreadable")
      end

      it "skips gitignored, empty and binary untracked files" do
        commit_file("a.rb", "1\n")
        commit_file(".gitignore", "ignored.rb\n")
        File.write(File.join(@dir, "ignored.rb"), "1\n")
        File.write(File.join(@dir, "empty.rb"), "")
        File.binwrite(File.join(@dir, "blob.bin"), "a\0b\n")
        File.write(File.join(@dir, "new.rb"), "1\n")
        changed = described_class.changed_lines("HEAD", root: @dir)
        expect(changed.keys.map { |path| File.basename(path) }).to eq(["new.rb"])
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
      # The SHA-named file is untracked, so the diff still yields only a.rb;
      # the file joins the map as fully changed via the untracked union (#295).
      expect(changed.transform_keys { |k| File.basename(k) }).to eq("a.rb" => Set[2], sha => (1..1))
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

  describe ".changed_paths (#307)" do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = File.realpath(dir)
        git("init", "-q")
        write("spec/kept_spec.rb", "1\n")
        write("spec/old_name_spec.rb", "1\n")
        write("spec/gone_spec.rb", "1\n")
        write("svc/spec/inner_spec.rb", "1\n")
        git("add", ".")
        git("commit", "-q", "-m", "base")
        example.run
      end
    end

    def git(*args)
      _, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args,
                                      chdir: @dir)
      raise err unless status.success?
    end

    def write(path, text)
      FileUtils.mkdir_p(File.dirname(File.join(@dir, path)))
      File.write(File.join(@dir, path), text)
    end

    def paths(root = @dir)
      described_class.changed_paths("HEAD", root: root)
    end

    it "lists changed and untracked paths as present and removed ones as deleted, sorted" do
      write("spec/kept_spec.rb", "2\n")
      write("spec/a_new_spec.rb", "1\n")
      File.delete(File.join(@dir, "spec/gone_spec.rb"))
      expect(paths).to eq(present: %w[spec/a_new_spec.rb spec/kept_spec.rb], deleted: %w[spec/gone_spec.rb])
    end

    it "counts a rename as a deletion of the old path and an addition of the new one" do
      git("mv", "spec/old_name_spec.rb", "spec/new_name_spec.rb")
      expect(paths).to eq(present: %w[spec/new_name_spec.rb], deleted: %w[spec/old_name_spec.rb])
    end

    it "lists only paths under the root, relative to it" do
      write("svc/spec/inner_spec.rb", "2\n")
      write("svc/spec/fresh_spec.rb", "1\n")
      write("spec/kept_spec.rb", "2\n")
      File.delete(File.join(@dir, "spec/gone_spec.rb"))
      expect(paths(File.join(@dir, "svc"))).to eq(present: %w[spec/fresh_spec.rb spec/inner_spec.rb], deleted: [])
    end

    it "leaves out untracked files git ignores" do
      write(".gitignore", "tmp/\n")
      write("tmp/scratch_spec.rb", "1\n")
      expect(paths[:present]).to eq([".gitignore"])
    end

    it "keeps paths with spaces, newlines and non-ASCII bytes whole, as UTF-8" do
      write("spec/kept_spec.rb", "2\n")
      write("spec/caf\u00e9 two_spec.rb", "1\n")
      write("spec/line\nbreak_spec.rb", "1\n")
      present = paths[:present]
      expect(present).to eq(["spec/caf\u00e9 two_spec.rb", "spec/kept_spec.rb", "spec/line\nbreak_spec.rb"])
      expect(present.map(&:encoding).uniq).to eq([Encoding::UTF_8])
    end

    # Without the -- separator git cannot tell the base commit from a file
    # of the same name and stops with "ambiguous argument".
    it "reads the diff when a file is named like the base commit" do
      base = Open3.capture3("git", "rev-parse", "HEAD", chdir: @dir).first.strip
      write(base, "1\n")
      write("spec/kept_spec.rb", "2\n")
      expect(paths[:present]).to eq([base, "spec/kept_spec.rb"])
    end

    it "lists a path whose name is not valid UTF-8, tagged UTF-8" do
      name = "spec/h\xE9llo_spec.rb".b
      begin
        File.binwrite(File.join(@dir, name), "1\n")
      rescue Errno::EILSEQ, Errno::EINVAL
        skip "this platform rejects filenames that are not valid UTF-8"
      end
      expect(paths[:present]).to eq([name.dup.force_encoding(Encoding::UTF_8)])
    end

    # shoulda-matchers in the wild: vendor/bundle untracked and NOT
    # gitignored, and --since enumerated every vendored gem's own spec
    # files (#504). Dependency trees are never changed source.
    it "never enumerates dependency trees, tracked or untracked (#504)" do
      write("vendor/bundle/ruby/3.3.0/gems/appraisal-2.5.0/spec/appraisal_spec.rb", "1\n")
      write("node_modules/left-pad/index.rb", "1\n")
      write("vendor/committed_gem/lib/x.rb", "1\n")
      git("add", "vendor/committed_gem/lib/x.rb")
      git("commit", "-q", "-m", "vendored")
      write("vendor/committed_gem/lib/x.rb", "2\n")
      write("spec/kept_spec.rb", "2\n")
      expect(paths[:present]).to eq(["spec/kept_spec.rb"])
    end

    it "shields the configured bundler path from .bundle/config (#504)" do
      write(".bundle/config", "BUNDLE_PATH: .bundle\n")
      write(".bundle/ruby/3.3.0/gems/diff-lcs-1.6.2/spec/diff_spec.rb", "1\n")
      write("spec/kept_spec.rb", "2\n")
      expect(paths[:present]).to eq([".bundle/config", "spec/kept_spec.rb"])
    end

    # YAML scalars may be quoted; the quotes are not part of the path.
    it "shields a quoted BUNDLE_PATH value (#567)" do
      write(".bundle/config", "BUNDLE_PATH: 'deps'\n")
      write("deps/ruby/3.3.0/gems/diff-lcs-1.6.2/spec/diff_spec.rb", "1\n")
      write("spec/kept_spec.rb", "2\n")
      expect(paths[:present]).to eq([".bundle/config", "spec/kept_spec.rb"])
    end

    # The same directory, spelled with . and .. segments, shields the
    # same tree: the prefix is the normalized path, not the raw scalar.
    it "shields a BUNDLE_PATH spelled with . and .. segments (#567)" do
      write(".bundle/config", %(BUNDLE_PATH: "./deps/../deps"\n))
      write("deps/ruby/3.3.0/gems/diff-lcs-1.6.2/spec/diff_spec.rb", "1\n")
      write("spec/kept_spec.rb", "2\n")
      expect(paths[:present]).to eq([".bundle/config", "spec/kept_spec.rb"])
    end

    # The shield prefix ends in a slash: a sibling directory that merely
    # shares the name's first bytes is project source, not the bundle.
    it "shields only the configured directory, not a same-prefix sibling (#567)" do
      write(".bundle/config", "BUNDLE_PATH: deps\n")
      write("deps/ruby/3.3.0/gems/diff-lcs-1.6.2/spec/diff_spec.rb", "1\n")
      write("deps2/kept_spec.rb", "2\n")
      expect(paths[:present]).to eq([".bundle/config", "deps2/kept_spec.rb"])
    end

    # ./deps and deps are the same directory: the leading ./ is spelling,
    # not part of the shield prefix.
    it "shields a BUNDLE_PATH spelled with a leading ./ (#567)" do
      write(".bundle/config", "BUNDLE_PATH: ./deps\n")
      write("deps/ruby/3.3.0/gems/diff-lcs-1.6.2/spec/diff_spec.rb", "1\n")
      write("spec/kept_spec.rb", "2\n")
      expect(paths[:present]).to eq([".bundle/config", "spec/kept_spec.rb"])
    end

    # BUNDLE_PATH: . installs the bundle into the project root - unusual
    # but valid. An empty normalized prefix matches every path, shielding
    # the whole tree from --since (#580).
    it "shields nothing when BUNDLE_PATH is the project root (#580)" do
      write(".bundle/config", "BUNDLE_PATH: .\n")
      write("lib/app.rb", "1\n")
      write("spec/kept_spec.rb", "2\n")
      expect(paths[:present]).to eq([".bundle/config", "lib/app.rb", "spec/kept_spec.rb"])
    end

    it "shields nothing when BUNDLE_PATH is ./ (#580)" do
      write(".bundle/config", "BUNDLE_PATH: ./\n")
      write("lib/app.rb", "1\n")
      expect(paths[:present]).to eq([".bundle/config", "lib/app.rb"])
    end

    it "refuses a ref that is not a commit, as a usage error" do
      expect { described_class.changed_paths("no-such-ref", root: @dir) }
        .to raise_error(Saboteur::ConfigError, /no-such-ref: not a commit/)
    end
  end
end

RSpec.describe Saboteur::Selection::GitDiff, ".deletion_only_files" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = File.realpath(dir)
      git("init", "-q")
      write("pure.rb", "a\nb\nc\nd\n")
      write("mixed.rb", "1\n2\n3\n4\n5\n6\n")
      git("add", ".")
      git("commit", "-q", "-m", "base")
      @base = `git -C #{@dir} rev-parse HEAD`.strip
      example.run
    end
  end

  def git(*args)
    _, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args,
                                    chdir: @dir)
    raise err unless status.success?
  end

  def write(path, text)
    File.write(File.join(@dir, path), text)
  end

  def commit_changes
    write("pure.rb", "a\nd\n")
    write("mixed.rb", "0\n1\n2\n3\n4\n6\n")
    git("commit", "-qam", "change")
  end

  it "lists a committed deletion-only file and not one that also adds lines, in either hunk order" do
    commit_changes
    expect(described_class.deletion_only_files(@base, root: @dir)).to eq([File.join(@dir, "pure.rb")])
  end

  it "reads plain diff output whatever the repository colors or external diff settings say" do
    git("config", "color.diff", "always")
    git("config", "diff.external", "echo")
    commit_changes
    expect(described_class.deletion_only_files(@base, root: @dir)).to eq([File.join(@dir, "pure.rb")])
  end

  it "compares against the merge base with the ref, not the index" do
    git("checkout", "-q", "-b", "topic")
    commit_changes
    expect(described_class.deletion_only_files("HEAD~1", root: @dir)).to eq([File.join(@dir, "pure.rb")])
  end

  it "resolves the toplevel when its path holds raw non-UTF-8 bytes" do
    original = @dir
    raw = File.join(File.dirname(@dir), "r\xE9pos".b + File.basename(@dir).b)
    begin
      File.rename(original, raw)
    rescue Errno::EILSEQ, Errno::EINVAL
      skip "this platform rejects filenames that are not valid UTF-8"
    end
    begin
      @dir = raw
      commit_changes
      expect(described_class.deletion_only_files(@base, root: raw)).to eq([File.join(raw, "pure.rb").b])
    ensure
      File.rename(raw, original)
    end
  end

  it "ends the revision list so a file named like the merge base is not read as an ambiguous argument" do
    commit_changes
    write(@base, "x\n")
    expect(described_class.deletion_only_files(@base, root: @dir)).to eq([File.join(@dir, "pure.rb")])
  end
end
