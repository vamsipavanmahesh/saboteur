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

  it "raises a saboteur error for an unknown ref" do
    Dir.mktmpdir do |dir|
      Open3.capture3("git", "init", "-q", chdir: dir)
      expect { described_class.changed_lines("nope", root: dir) }.to raise_error(Saboteur::Error, /git/)
    end
  end
end
