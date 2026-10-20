# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Engine::DataInputs, "pins" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def touch(relative)
    path = File.join(@root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "x")
    path
  end

  it "lists dot files and dot dirs under the fixture dirs" do
    keep = touch("spec/fixtures/.keep")
    hidden = touch("spec/fixtures/.hidden/a.yml")
    plain = touch("spec/fixtures/b.yml")
    expect(described_class.files(@root)).to eq([keep, hidden, plain].sort)
  end

  it "matches only paths under the root, not a sibling dir that shares its name" do
    expect(described_class.match?(@root, File.join(@root, "config/database.yml"))).to be(true)
    expect(described_class.match?(@root, "/elsewhere/config/database.yml")).to be(false)
    expect(described_class.match?(@root, "#{@root}x/config/database.yml", extra: ["**/*.yml"])).to be(false)
    expect(described_class.match?(@root, @root)).to be(false)
  end

  it "keeps a * inside one directory, and lets dot files and braces match" do
    expect(described_class.match?(@root, File.join(@root, "config/sub/x.yml"))).to be(false)
    expect(described_class.match?(@root, File.join(@root, "spec/fixtures/.keep"))).to be(true)
    expect(described_class.match?(@root, File.join(@root, "data/a.csv"), extra: ["data/*.{csv,json}"])).to be(true)
  end
end
