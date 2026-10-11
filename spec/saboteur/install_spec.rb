# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "yaml"
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
    expect(results.map { |r| [r.status, r.path] }).to eq([[:created, ".saboteur.yml"], [:created, "bin/saboteur"],
                                       [:appended, ".gitignore"]])
    expect(read(".gitignore")).to eq(".saboteur/\n")
  end

  it "writes a config that loads through the real Config with Rails defaults" do
    install
    data = YAML.safe_load_file(File.join(@root, ".saboteur.yml"))
    config = Saboteur::Config.new(data, root: @root)
    expect([config["rails"], config["include"], config["require"], config["jobs"]])
      .to eq([true, ["app/**/*.rb"], ["./config/environment"], 4])
  end

  it "matches the Rails block documented in the README" do
    readme = File.read(File.expand_path("../../README.md", __dir__))
    documented = YAML.safe_load(readme[/^### Rails apps\n.*?```yaml\n(.*?)```/m, 1])
    generated = YAML.safe_load(described_class::CONFIG)
    expect(generated.slice(*documented.keys)).to eq(documented)
  end

  it "makes bin/saboteur executable and boots in the test environment" do
    install
    expect(File.executable?(File.join(@root, "bin/saboteur"))).to be(true)
    expect(read("bin/saboteur")).to include('ENV["RAILS_ENV"] ||= "test"', "Gem.bin_path")
  end

  it "does not overwrite existing files and reports them as skipped" do
    File.write(File.join(@root, ".saboteur.yml"), "include: [lib/**/*.rb]\n")
    FileUtils.mkdir_p(File.join(@root, "bin"))
    File.write(File.join(@root, "bin/saboteur"), "custom")
    results = install
    expect(results.first(2).map(&:status)).to eq(%i[skipped skipped])
    expect(read(".saboteur.yml")).to eq("include: [lib/**/*.rb]\n")
    expect(read("bin/saboteur")).to eq("custom")
  end

  it "overwrites with force" do
    File.write(File.join(@root, ".saboteur.yml"), "old")
    expect(install(force: true).first.status).to eq(:overwritten)
    expect(read(".saboteur.yml")).to eq(described_class::CONFIG)
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
    expect(installer.gemfile_hint).to be_nil
  end
end
