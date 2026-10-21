# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "saboteur/install"

RSpec.describe Saboteur::Install do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def read(path) = File.read(File.join(@root, path))
  def install(**) = described_class.new(root: @root, **).call

  it "creates the config, the binstub and the gitignore entry" do
    results = install
    expected = [[:created, "config/saboteur.rb"], [:created, "bin/saboteur"], [:appended, ".gitignore"]]
    expect(results.map { |result| [result.status, result.path] }).to eq(expected)
    expect(read(".gitignore")).to eq(".saboteur/\n")
  end

  it "reads a Gemfile and .gitignore with non-ASCII content under a non-UTF-8 locale" do
    File.write(File.join(@root, "Gemfile"), "# caf\u00E9\ngem \"saboteur\"\n")
    File.write(File.join(@root, ".gitignore"), "caf\u00E9\n")
    allow(File).to receive(:read).and_wrap_original do |original, *args|
      original.call(*args).force_encoding(Encoding::US_ASCII)
    end
    installer = described_class.new(root: @root)
    expect(installer.gemfile_hint).to eq(described_class::RUN_HINT)
    ignore = installer.call.find { |result| result.path == ".gitignore" }
    expect(ignore.status).to eq(:appended)
    expect(File.binread(File.join(@root, ".gitignore"))).to eq("caf\xC3\xA9\n.saboteur/\n".b)
  end

  it "writes a config that loads through the real Config with Rails defaults" do
    install
    config = Saboteur::Config.load(root: @root)
    expect([config["rails"], config["include"], config["require"], config["jobs"]])
      .to eq([true, ["app/**/*.rb"], ["./config/environment"], 4])
  end

  it "matches the Rails block documented in the README" do
    readme = File.read(File.expand_path("../../README.md", __dir__), encoding: "UTF-8")
    documented = readme[/^### Rails apps\n.*?```ruby\n(.*?)```/m, 1]
    code = ->(text) { text.scan(/^\s*(c\.\w+ = [^#\n]+)/).flatten.map { |line| line.strip.gsub(/\s+/, " ") } }
    expect(code.call(described_class::CONFIG)).to include(*code.call(documented))
    expect(code.call(documented)).to include('c.require = ["./config/environment"]')
  end

  it "makes bin/saboteur executable and boots in the test environment" do
    install
    expect(File.executable?(File.join(@root, "bin/saboteur"))).to be(true)
    expect(read("bin/saboteur")).to include('ENV["RAILS_ENV"] ||= "test"', "Gem.bin_path")
  end

  it "does not overwrite existing files and reports them as skipped" do
    FileUtils.mkdir_p(File.join(@root, "config"))
    File.write(File.join(@root, "config", "saboteur.rb"), "Saboteur.configure { |c| c.include = [\"lib/**/*.rb\"] }\n")
    FileUtils.mkdir_p(File.join(@root, "bin"))
    File.write(File.join(@root, "bin/saboteur"), "custom")
    results = install
    expect(results.first(2).map(&:status)).to eq(%i[skipped skipped])
    expect(read("config/saboteur.rb")).to eq("Saboteur.configure { |c| c.include = [\"lib/**/*.rb\"] }\n")
    expect(read("bin/saboteur")).to eq("custom")
  end

  it "overwrites with force" do
    FileUtils.mkdir_p(File.join(@root, "config"))
    File.write(File.join(@root, "config", "saboteur.rb"), "old")
    expect(install(force: true).first.status).to eq(:overwritten)
    expect(read("config/saboteur.rb")).to eq(described_class::CONFIG)
  end

  it "is idempotent on the gitignore and keeps existing content" do
    File.write(File.join(@root, ".gitignore"), "log/*")
    install
    expect(install.last.status).to eq(:unchanged)
    expect(read(".gitignore")).to eq("log/*\n.saboteur/\n")
  end

  it "hints at the Gemfile only when saboteur is missing, and never edits it" do
    File.write(File.join(@root, "Gemfile"), "source 'x'\n")
    installer = described_class.new(root: @root)
    installer.call
    expect(installer.gemfile_hint).to include('gem "saboteur"')
    expect(read("Gemfile")).to eq("source 'x'\n")
    File.write(File.join(@root, "Gemfile"), "gem \"saboteur\", group: :test\n")
    expect(installer.gemfile_hint).to eq(described_class::RUN_HINT)
  end

  it "does not write through a dangling symlink without force" do
    target = File.join(@root, "outside.yml")
    FileUtils.mkdir_p(File.join(@root, "config"))
    File.symlink(target, File.join(@root, "config", "saboteur.rb"))
    File.symlink(File.join(@root, "outside-ignore"), File.join(@root, ".gitignore"))
    results = install
    expect(results.map(&:status)).to eq(%i[skipped created skipped])
    expect(File.exist?(target)).to be(false)
    expect(File.exist?(File.join(@root, "outside-ignore"))).to be(false)
    expect(File.symlink?(File.join(@root, "config", "saboteur.rb"))).to be(true)
  end

  it "replaces a symlink with a regular file under force instead of writing through it" do
    FileUtils.mkdir_p(File.join(@root, "config"))
    target = File.join(@root, "outside.yml")
    File.write(target, "keep")
    File.symlink(target, File.join(@root, "config", "saboteur.rb"))
    expect(install(force: true).first.status).to eq(:overwritten)
    expect(File.symlink?(File.join(@root, "config", "saboteur.rb"))).to be(false)
    expect(File.read(target)).to eq("keep")
    expect(read("config/saboteur.rb")).to eq(described_class::CONFIG)
  end

  describe "symlinks" do
    let(:outside) { Dir.mktmpdir }

    after { FileUtils.remove_entry(outside) }

    it "does not write or chmod through a symlinked bin directory without force" do
      File.symlink(outside, File.join(@root, "bin"))
      results = install
      expect(results.map(&:status)).to eq(%i[created skipped appended])
      expect(Dir.children(outside)).to eq([])
      expect(File.symlink?(File.join(@root, "bin"))).to be(true)
    end

    it "replaces a symlinked bin directory under force and leaves the target alone" do
      File.write(File.join(outside, "other"), "keep")
      File.symlink(outside, File.join(@root, "bin"))
      install(force: true)
      expect(File.symlink?(File.join(@root, "bin"))).to be(false)
      expect(File.executable?(File.join(@root, "bin/saboteur"))).to be(true)
      expect(Dir.children(outside)).to eq(["other"])
    end

    it "does not modify a live .gitignore symlink without force" do
      target = File.join(outside, "ignore")
      File.write(target, "log/*\n")
      File.symlink(target, File.join(@root, ".gitignore"))
      expect(install.last.status).to eq(:skipped)
      expect(File.read(target)).to eq("log/*\n")
    end

    it "replaces a live .gitignore symlink with a regular file under force, keeping its lines" do
      target = File.join(outside, "ignore")
      File.write(target, "log/*\n")
      File.symlink(target, File.join(@root, ".gitignore"))
      expect(install(force: true).last.status).to eq(:overwritten)
      expect(File.symlink?(File.join(@root, ".gitignore"))).to be(false)
      expect(read(".gitignore")).to eq("log/*\n.saboteur/\n")
      expect(File.read(target)).to eq("log/*\n")
    end
  end

  describe "exact results and modes" do
    let(:outside) { Dir.mktmpdir }

    after { FileUtils.remove_entry(outside) }

    it "gives the binstub mode 0755 exactly" do
      install
      expect(File.stat(File.join(@root, "bin/saboteur")).mode & 0o777).to eq(0o755)
    end

    it "hints at the Gemfile even when there is no Gemfile at all" do
      expect(described_class.new(root: @root).gemfile_hint).to eq(described_class::GEMFILE_HINT)
    end

    it "overwrites a dangling symlink under force and reports it as overwritten" do
      FileUtils.mkdir_p(File.join(@root, "config"))
      File.symlink(File.join(outside, "missing.yml"), File.join(@root, "config", "saboteur.rb"))
      expect(install(force: true).first.status).to eq(:overwritten)
      expect(File.symlink?(File.join(@root, "config", "saboteur.rb"))).to be(false)
      expect(File.exist?(File.join(outside, "missing.yml"))).to be(false)
    end

    it "names .gitignore in its skipped and unchanged results" do
      File.write(File.join(@root, ".gitignore"), ".saboteur/\n")
      expect(install.last).to eq(described_class::Result.new(:unchanged, ".gitignore"))
      FileUtils.rm(File.join(@root, ".gitignore"))
      File.symlink(File.join(outside, "gone"), File.join(@root, ".gitignore"))
      expect(install.last).to eq(described_class::Result.new(:skipped, ".gitignore"))
    end

    it "replaces a live .gitignore symlink that already lists the entry, without duplicating it" do
      target = File.join(outside, "ignore")
      File.write(target, "log/*\n.saboteur/\n")
      File.symlink(target, File.join(@root, ".gitignore"))
      expect(install(force: true).last).to eq(described_class::Result.new(:overwritten, ".gitignore"))
      expect(File.symlink?(File.join(@root, ".gitignore"))).to be(false)
      expect(read(".gitignore")).to eq("log/*\n.saboteur/\n")
    end
  end
end
