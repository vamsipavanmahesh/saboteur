# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::DirtyTreeWarning do
  def change(path, tracked: true)
    Saboteur::WorkingTree::Change.new(path: path, tracked: tracked)
  end

  def state(*changes)
    Saboteur::WorkingTree::State.new(head: "abc", dirty: !changes.empty?, changed_files: changes.size,
                                     changes: changes)
  end

  def warning(*changes, include: ["lib/**/*.rb"], exclude: [], setup_files: ["config/saboteur.rb"],
              root: Dir.pwd)
    described_class.new(state(*changes), include: include, exclude: exclude, setup_files: setup_files,
                                         root: root).to_s
  end

  it "says nothing on a clean or unknown tree" do
    expect(warning).to be_nil
    unknown = described_class.new(Saboteur::WorkingTree::UNKNOWN, include: [], exclude: [], setup_files: [],
                                                                  root: Dir.pwd)
    expect(unknown.to_s).to be_nil
  end

  it "splits the count into the mutation scope, outside it and setup files, each tracked and untracked" do
    text = warning(change("lib/a.rb"), change("lib/new.rb", tracked: false),
                   change("Gemfile"), change("notes/a.md", tracked: false), change("notes/b.md", tracked: false),
                   change("config/saboteur.rb", tracked: false))

    expect(text).to start_with("saboteur: warning: 6 uncommitted change(s) in the working tree: " \
                               "2 inside the mutation scope (1 tracked, 1 untracked), " \
                               "3 outside it (1 tracked, 2 untracked), " \
                               "1 saboteur setup file(s) (0 tracked, 1 untracked).")
    expect(text).to include("\n  inside the mutation scope: lib/a.rb, lib/new.rb\n")
    expect(text).to include("\n  setup files: config/saboteur.rb\n")
    expect(text).to end_with("Mutants run your code and could alter or delete files; " \
                             "run on a clean, committed tree or a CI checkout.")
  end

  it "says when none of the changes is in the mutation scope and names no scope paths" do
    notes = Array.new(3969) { |index| change("notes/#{index}.md", tracked: false) }
    text = warning(*notes, change("config/saboteur.rb", tracked: false), change("Gemfile.saboteur", tracked: false),
                   change("Gemfile.saboteur.lock", tracked: false),
                   setup_files: %w[config/saboteur.rb Gemfile.saboteur Gemfile.saboteur.lock])

    expect(text).to include("3972 uncommitted change(s) in the working tree: none inside the mutation scope, " \
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
  end

  it "matches the include patterns with the filesystem's case sensitivity (#503 review)" do
    expected = if RUBY_PLATFORM.include?("darwin") then "1 inside the mutation scope"
               else "none inside the mutation scope"
               end
    expect(warning(change("Lib/A.rb"))).to include(expected)
  end

  it "keeps a setup file that the include patterns cover in the setup group only" do
    text = warning(change("config/saboteur.rb"), include: ["**/*.rb"])

    expect(text).to include("none inside the mutation scope, 0 outside it (0 tracked, 0 untracked), " \
                            "1 saboteur setup file(s) (1 tracked, 0 untracked)")
  end
end
