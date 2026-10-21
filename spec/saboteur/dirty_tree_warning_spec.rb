# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe Saboteur::DirtyTreeWarning do
  def change(path, tracked: true)
    Saboteur::WorkingTree::Change.new(path: path, tracked: tracked)
  end

  def state(*changes)
    Saboteur::WorkingTree::State.new(head: "abc", dirty: !changes.empty?, changed_files: changes.size,
                                     changes: changes)
  end

  def warning(*changes, included: [], include: ["lib/**/*.rb"], exclude: [], setup_files: ["config/saboteur.rb"])
    described_class.new(state(*changes), included: included, include: include, exclude: exclude,
                                         setup_files: setup_files, root: Dir.pwd).to_s
  end

  it "says nothing on a clean or unknown tree" do
    expect(warning).to be_nil
    unknown = described_class.new(Saboteur::WorkingTree::UNKNOWN, included: [], include: [], exclude: [],
                                                                  setup_files: [], root: Dir.pwd)
    expect(unknown.to_s).to be_nil
  end

  it "splits the count into the mutation scope, outside it and setup files, each tracked and untracked" do
    text = warning(change("lib/a.rb"), change("lib/new.rb", tracked: false),
                   change("Gemfile"), change("notes/a.md", tracked: false), change("notes/b.md", tracked: false),
                   change("config/saboteur.rb", tracked: false))

    expect(text).to start_with("saboteur: warning: 6 uncommitted or untracked change(s) in the working tree: " \
                               "2 inside the mutation scope (1 tracked, 1 untracked), " \
                               "3 outside it (1 tracked, 2 untracked), " \
                               "1 saboteur setup file(s) (0 tracked, 1 untracked).")
    expect(text).to include("\n  inside the mutation scope: lib/a.rb, lib/new.rb\n")
    expect(text).to include("\n  setup files: config/saboteur.rb\n")
    expect(text).to end_with("\n  Fix: commit or stash your changes first, or run on a CI checkout - " \
                             "mutants run your code and could alter or delete files.")
  end

  it "says uncommitted or untracked so a tree of only scratch files is not read as edits (#604)" do
    text = warning(change("NOTES.md", tracked: false))

    expect(text).to start_with("saboteur: warning: 1 uncommitted or untracked change(s) in the working tree: " \
                               "none inside the mutation scope, 1 outside it (0 tracked, 1 untracked).")
  end

  it "says when none of the changes is in the mutation scope and names no scope paths" do
    notes = Array.new(3969) { |index| change("notes/#{index}.md", tracked: false) }
    text = warning(*notes, change("config/saboteur.rb", tracked: false), change("Gemfile.saboteur", tracked: false),
                   change("Gemfile.saboteur.lock", tracked: false),
                   setup_files: %w[config/saboteur.rb Gemfile.saboteur Gemfile.saboteur.lock])

    expect(text).to include("3972 uncommitted or untracked change(s) in the working tree: " \
                            "none inside the mutation scope, " \
                            "3969 outside it (0 tracked, 3969 untracked), 3 saboteur setup file(s)")
    expect(text).not_to include("inside the mutation scope:")
    expect(text).to include("setup files: config/saboteur.rb, Gemfile.saboteur, Gemfile.saboteur.lock")
    expect(text.lines.size).to eq(3)
  end

  it "names at most five paths per group and says how many more there are" do
    sources = Array.new(7) { |index| change("lib/f#{index}.rb") }
    text = warning(*sources)

    expect(text).to include("inside the mutation scope: lib/f0.rb, lib/f1.rb, lib/f2.rb, lib/f3.rb, lib/f4.rb " \
                            "and 2 more\n")
  end

  it "matches a leading ./ include and an absolute include under the root (#503 review)" do
    dot = warning(change("lib/a.rb"), include: ["./lib/**/*.rb"])
    absolute = warning(change("lib/a.rb"), include: [File.join(Dir.pwd, "lib/**/*.rb")])

    [dot, absolute].each do |text|
      expect(text).to include("1 inside the mutation scope (1 tracked, 0 untracked)")
    end
  end

  it "does not match an absolute include outside the root" do
    text = warning(change("lib/a.rb"), include: ["/elsewhere/lib/**/*.rb"])

    expect(text).to include("none inside the mutation scope, 1 outside it")
  end

  it "leaves an excluded file and a non-Ruby file under include outside the scope" do
    text = warning(change("lib/a.rb"), change("lib/gen/b.rb"), change("lib/data.yml"),
                   exclude: ["lib/gen/**/*.rb"])

    expect(text).to include("1 inside the mutation scope (1 tracked, 0 untracked), 2 outside it")
  end

  it "counts a deleted file by its path, so a removed source is still in the scope" do
    expect(warning(change("lib/gone.rb"))).to include("1 inside the mutation scope")
  end

  it "derives the trial lockfile with bundler's rule: gems.rb locks to gems.locked (#503 review)" do
    files = described_class.setup_files(Dir.pwd, config_path: nil, gemfile: "gems.rb")
    expect(files).to eq(["config/saboteur.rb", "gems.rb", "gems.locked"])
    other = described_class.setup_files(Dir.pwd, config_path: nil, gemfile: "Gemfile.saboteur")
    expect(other).to eq(["config/saboteur.rb", "Gemfile.saboteur", "Gemfile.saboteur.lock"])
    nested = described_class.setup_files(Dir.pwd, config_path: nil, gemfile: "ci/gems.rb")
    expect(nested).to eq(["config/saboteur.rb", "ci/gems.rb", "ci/gems.locked"])
  end

  it "keeps a setup file that the include patterns cover in the setup group only" do
    text = warning(change("config/saboteur.rb"), include: ["**/*.rb"])

    expect(text).to include("none inside the mutation scope, 0 outside it (0 tracked, 0 untracked), " \
                            "1 saboteur setup file(s) (1 tracked, 0 untracked)")
  end

  it "names no setup group when no setup file changed" do
    expect(warning(change("lib/a.rb"))).not_to include("setup file")
  end

  it "counts a file the run includes even when the patterns alone miss it" do
    expect(warning(change("Lib/a.rb"), included: ["Lib/a.rb"])).to include("inside the mutation scope: Lib/a.rb")
  end

  it "leaves a non-Ruby file that an include pattern matches outside the scope" do
    expect(warning(change("lib/data.yml"), include: ["lib/**/*"])).to include("none inside the mutation scope")
  end

  describe ".for" do
    let(:root) { File.realpath(Dir.mktmpdir("saboteur-dirty-")) }

    after { FileUtils.remove_entry(root) }

    def write(path)
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), "x = 1\n")
    end

    def git(*args)
      Open3.capture2e("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: root)
    end

    def dirty_tree(*paths)
      write("README.md")
      git("init", "-q")
      git("add", ".")
      git("commit", "-q", "-m", "first")
      paths.each { |path| write(path) }
    end

    def text(include: ["lib/**/*.rb"], root_spelling: root, config_path: nil, gemfile: nil)
      config = Saboteur::Config.new({ "include" => include }, root: root_spelling)
      described_class.for(config, config_path: config_path, gemfile: gemfile)
    end

    # #638: the documented Gemfile.saboteur sidecar setup is tool-owned, so
    # it never counts as a working-tree change.
    it "stays quiet when only the documented sidecar Gemfile setup is uncommitted (#638)" do
      dirty_tree("Gemfile.saboteur", "Gemfile.saboteur.lock")

      expect(text(gemfile: File.join(root, "Gemfile.saboteur"))).to be_nil
    end

    it "counts only the non-tool files when the sidecar setup is present (#638)" do
      dirty_tree("Gemfile.saboteur", "Gemfile.saboteur.lock", "notes.md")

      warning = text(gemfile: File.join(root, "Gemfile.saboteur"))
      expect(warning).to start_with("saboteur: warning: 1 uncommitted or untracked change(s)")
    end

    # A bracketed sidecar name must not glob: "g/[ab].gemfile" excludes
    # only a file literally named "[ab].gemfile", never g/a.gemfile or
    # g/b.gemfile.
    it "treats a bracketed BUNDLE_GEMFILE name as a literal path, not a glob (#638)" do
      dirty_tree("g/a.gemfile", "g/b.gemfile")

      warning = text(gemfile: "g/[ab].gemfile")
      expect(warning).to start_with("saboteur: warning: 2 uncommitted or untracked change(s)")
    end

    it "does not raise when the BUNDLE_GEMFILE directory does not exist (#638)" do
      dirty_tree("notes.md")

      warning = text(gemfile: "no/such/dir/Gemfile.saboteur")
      expect(warning).to start_with("saboteur: warning: 1 uncommitted or untracked change(s)")
    end

    it "excludes nothing when BUNDLE_GEMFILE points outside the repo (#638)" do
      dirty_tree("Gemfile.lock")
      outside = Dir.mktmpdir("saboteur-outside-")

      warning = text(gemfile: File.join(outside, "Gemfile.saboteur"))
      expect(warning).to start_with("saboteur: warning: 1 uncommitted or untracked change(s)")
    ensure
      FileUtils.remove_entry(outside) if outside
    end

    it "hands the configured output paths to the tree scan as the ignored list" do
      config = Saboteur::Config.new({ "cache_dir" => "tmp/custom_cache" }, root: root)
      captured = nil
      allow(Saboteur::WorkingTree).to receive(:new) do |scan_root, **kwargs|
        captured = [scan_root, kwargs]
        double("tree", state: Saboteur::WorkingTree::UNKNOWN)
      end

      described_class.for(config, config_path: nil, gemfile: nil)

      expect(captured).to eq([config.root, { ignored: config.ignored_tree_paths(gemfile: nil) }])
    end

    it "matches ./ and absolute include patterns the way the run does (#503)" do
      dirty_tree("lib/a.rb", "lib/nested/z.rb")

      expect(text(include: ["./lib/**/*.rb"])).to include("inside the mutation scope: lib/a.rb, lib/nested/z.rb")
      expect(text(include: ["#{root}/lib/**/*.rb"])).to include("2 inside the mutation scope")
    end

    it "names the setup files by their physical path when the root is reached through a symlink" do
      dirty_tree("config/saboteur.rb", "Gemfile.saboteur", "Gemfile.saboteur.lock", "lib/a.rb")
      link = "#{root}-link"
      File.symlink(root, link)

      warning = text(root_spelling: link, gemfile: File.join(link, "Gemfile.saboteur"))
      expect(warning).to include("setup files: config/saboteur.rb\n")
      expect(warning).to include("inside the mutation scope: lib/a.rb\n")
    ensure
      FileUtils.rm_f(link)
    end

    it "treats the root Gemfile as an ordinary file and reads a relative config path against the root" do
      dirty_tree("Gemfile", "Gemfile.lock", "ci/saboteur.rb")

      warning = Dir.chdir(Dir.tmpdir) { text(config_path: "ci/saboteur.rb", gemfile: "Gemfile") }
      expect(warning).to include("2 outside it (0 tracked, 2 untracked), 1 saboteur setup file(s)")
      expect(warning).to include("setup files: ci/saboteur.rb\n")
    end

    it "leaves out a setup file outside the root" do
      dirty_tree("Gemfile.saboteur", "notes.md")

      warning = text(config_path: File.join(Dir.tmpdir, "elsewhere.rb"), gemfile: File.join(root, "Gemfile.saboteur"))
      expect(warning).to start_with("saboteur: warning: 1 uncommitted or untracked change(s)")
    end

    it "counts a deleted source under a ./ pattern, resolved against the root, inside the scope" do
      dirty_tree("lib/gone.rb")
      git("add", ".")
      git("commit", "-q", "-m", "second")
      File.delete(File.join(root, "lib/gone.rb"))

      warning = Dir.chdir(Dir.tmpdir) { text(include: ["./lib/**/*.rb"]) }
      expect(warning).to include("inside the mutation scope: lib/gone.rb\n")
    end

    it "reads a relative BUNDLE_GEMFILE against the root and excludes that sidecar (#638)" do
      dirty_tree("Gemfile.saboteur", "Gemfile.saboteur.lock")

      expect(Dir.chdir(Dir.tmpdir) { text(gemfile: "Gemfile.saboteur") }).to be_nil
    end

    it "says nothing on a clean tree" do
      dirty_tree

      expect(text).to be_nil
    end
  end
end
