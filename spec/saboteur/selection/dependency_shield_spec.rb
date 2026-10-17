# SPDX-License-Identifier: MIT
# frozen_string_literal: true

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
  end
end
