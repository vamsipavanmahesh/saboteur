# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "timeout"
require "tmpdir"
require "fileutils"

RSpec.describe Saboteur::Selection::DependencyShield do
  around do |example|
    Dir.mktmpdir("shield-") do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def write_config(text)
    FileUtils.mkdir_p(File.join(@root, ".bundle"))
    File.write(File.join(@root, ".bundle", "config"), text)
  end

  describe ".bundler_path (#567 dogfood survivors)" do
    it "is nil when there is no .bundle/config at all" do
      expect(described_class.bundler_path(@root)).to be_nil
    end

    it "is nil when the config sets no BUNDLE_PATH" do
      write_config("BUNDLE_JOBS: 4\n")
      expect(described_class.bundler_path(@root)).to be_nil
    end

    it "is nil when BUNDLE_PATH is empty" do
      write_config("BUNDLE_PATH:\n")
      expect(described_class.bundler_path(@root)).to be_nil
    end

    it "is nil when BUNDLE_PATH is absolute (the system bundle, outside the tree)" do
      write_config("BUNDLE_PATH: /var/gems\n")
      expect(described_class.bundler_path(@root)).to be_nil
    end

    it "strips a quoted scalar before prefixing" do
      write_config("BUNDLE_PATH: \"deps\"\n")
      expect(described_class.bundler_path(@root)).to eq("deps/")
    end

    # A colon is a legal directory-name character on Linux: only the
    # first ":" splits the key from the value.
    it "keeps a colon inside the value" do
      write_config("BUNDLE_PATH: C:/deps\n")
      expect(described_class.bundler_path(@root)).to eq("C:/deps/")
    end

    # Bundler::YAMLSerializer#strip_comment: a # after the first
    # character starts a comment, inside quotes or not - the installed
    # serializer parses "BUNDLE_PATH: deps # project gems" as "deps".
    it "strips an inline comment like Bundler::YAMLSerializer" do
      write_config("BUNDLE_PATH: deps # project gems\n")
      expect(described_class.bundler_path(@root)).to eq("deps/")
    end

    # Bundler's regex only strips quotes when the closing quote ends the
    # line: with a comment after it the whole thing is a bare scalar, and
    # the serializer keeps the quote characters in the path.
    it "keeps the quotes when a comment follows the closing quote" do
      write_config("BUNDLE_PATH: \"deps\" # project gems\n")
      expect(described_class.bundler_path(@root)).to eq('"deps"/')
    end

    it "strips a comment even inside quotes, as the installed serializer does" do
      write_config("BUNDLE_PATH: \"deps # not a comment to a human\"\n")
      expect(described_class.bundler_path(@root)).to eq("deps/")
    end

    # A value that starts with # is data, not a comment, to the
    # serializer ("BUNDLE_PATH: # odd" parses as "# odd" ... but the
    # leading # only survives when it leads the value).
    it "keeps a leading # as part of the path" do
      write_config("BUNDLE_PATH: \"#deps\"\n")
      expect(described_class.bundler_path(@root)).to eq("#deps/")
    end

    # A NUL byte in the value makes File.expand_path raise ArgumentError;
    # an unreadable config means no shield, like a read failure, not a
    # crash.
    it "is nil when BUNDLE_PATH contains a NUL byte" do
      write_config("BUNDLE_PATH: \"de\0ps\"\n")
      expect(described_class.bundler_path(@root)).to be_nil
    end

    # A FIFO is not a regular file: opening it for read would block until
    # a writer appears, so the shield must skip it, promptly.
    it "is nil promptly when .bundle/config is a FIFO" do
      FileUtils.mkdir_p(File.join(@root, ".bundle"))
      system("mkfifo", File.join(@root, ".bundle", "config")) || raise("mkfifo failed")
      result = :unset
      Timeout.timeout(2) { result = described_class.bundler_path(@root) }
      expect(result).to be_nil
    end

    # A single quote character is one char, not a quoted string: with no
    # closing quote there is nothing to strip, and the " is the path.
    it "keeps a lone quote character as the path" do
      write_config("BUNDLE_PATH: \"\n")
      expect(described_class.bundler_path(@root)).to eq('"/')
    end

    # Two matching quotes and nothing between them: the empty bundle path
    # means no shield, like an empty bare value.
    it "is nil when BUNDLE_PATH is a quoted empty string" do
      write_config("BUNDLE_PATH: \"\"\n")
      expect(described_class.bundler_path(@root)).to be_nil
    end

    it "strips single quotes like double quotes" do
      write_config("BUNDLE_PATH: 'deps'\n")
      expect(described_class.bundler_path(@root)).to eq("deps/")
    end

    # Mismatched quotes do not pair: the value is a bare scalar that
    # happens to start with a quote character.
    it "keeps mismatched quotes as part of the path" do
      write_config("BUNDLE_PATH: \"deps'\n")
      expect(described_class.bundler_path(@root)).to eq("\"deps'/")
    end

    # An opening quote with no close is a bare scalar: Bundler's regex
    # only pairs quotes at both ends, so the " stays in the path.
    it "keeps an unbalanced opening quote as part of the path" do
      write_config("BUNDLE_PATH: \"deps\n")
      expect(described_class.bundler_path(@root)).to eq('"deps/')
    end
  end

  describe ".reject_trees (#567 dogfood survivors)" do
    # The root can arrive relative (a bare "." from a CLI default): the
    # bundler prefix is still absolute, so the comparison base must be
    # expanded, not taken as given.
    it "shields the bundler path when the root is relative" do
      write_config("BUNDLE_PATH: deps\n")
      Dir.chdir(@root) do
        expect(described_class.reject_trees(["deps/a.rb", "lib/b.rb"], ".")).to eq(["lib/b.rb"])
      end
    end
  end
end
