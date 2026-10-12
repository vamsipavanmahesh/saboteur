# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine::SubjectSelection do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:source) { "module Shop\n  class Cart\n    def total = 1\n    def self.empty = new\n  end\nend\n" }

  def write(name, text)
    File.join(@root, name).tap { |path| File.write(path, text) }
  end

  def select(files, **settings)
    config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)
    described_class.new(config, diagnostics).select(files)
  end

  it "finds every def in the files" do
    expect(select([write("cart.rb", source)]).map(&:id)).to eq(["Shop::Cart#total", "Shop::Cart.empty"])
  end

  it "keeps subjects matching --subject patterns, including namespace prefixes" do
    file = write("cart.rb", source)
    expect(select([file], subjects: ["Shop::Cart.empty"]).map(&:id)).to eq(["Shop::Cart.empty"])
    expect(select([file], subjects: ["Shop"]).size).to eq(2)
    expect(select([file], subjects: ["Sho"])).to be_empty
  end

  # Patterns are names, not globs: "Item*" matches nothing, and a silent
  # empty run looks like a clean one.
  it "warns about a --subject pattern that matches no subject" do
    select([write("cart.rb", source)], subjects: ["Shop::Cart", "Cart*"])
    expect(diagnostics.warnings).to eq(["--subject Cart* matches no subject (patterns are names like " \
                                        "Klass, Klass#meth or Klass.meth, not globs)"])
  end

  it "keeps only methods with a line changed since the ref" do
    file = write("cart.rb", source)
    git = lambda { |*args|
      Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
    }
    git.call("init", "-q")
    git.call("add", ".")
    git.call("commit", "-q", "-m", "base")
    File.write(file, source.sub("def total = 1", "def total = 2"))
    expect(select([file], since: "HEAD").map(&:id)).to eq(["Shop::Cart#total"])
  end

  it "keeps --since working when some selected files have no change" do
    changed = write("cart.rb", source)
    untouched = write("other.rb", "class Other\n  def x = 1\nend\n")
    git = lambda { |*args|
      Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
    }
    git.call("init", "-q")
    git.call("add", ".")
    git.call("commit", "-q", "-m", "base")
    File.write(changed, source.sub("def total = 1", "def total = 2"))
    expect(select([changed, untouched], since: "HEAD").map(&:id)).to eq(["Shop::Cart#total"])
  end

  it "reports only the first parse error of a file" do
    select([write("broken.rb", "class X\n  def (\n  def )\nend\n")])
    expect(diagnostics.warnings.size).to eq(1)
  end

  it "warns about files that do not parse and skips them" do
    expect(select([write("broken.rb", "class X\n  def (\nend\n")])).to be_empty
    expect(diagnostics.warnings.first).to start_with("broken.rb does not parse")
    expect(diagnostics.discovery_failures.map(&:to_h)).to eq([
                                                               { file: File.join(@root, "broken.rb"),
                                                                 reason: "invalid_file_syntax" }
                                                             ])
    expect(diagnostics.discovery_failures.first.file).to be_frozen
  end
end
