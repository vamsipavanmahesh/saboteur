# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "stringio"

RSpec.describe Saboteur::CLI::InitCommand do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def run_init(dir, *args)
    Dir.chdir(dir) { Saboteur::CLI.new(["init", *args], out: out, err: err).call }
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  it "writes a config that loads with the rspec integration and prints the next commands" do
    expect(run_init(@dir)).to eq(0)
    config = Saboteur::Config.load(root: @dir)
    expect([config["integration"], config["threshold"]]).to eq(["rspec", 60])
    expect(out.string).to eq("wrote config/saboteur.rb\n\nNext:\n  saboteur doctor\n  " \
                             "saboteur run --since origin/main\n  saboteur survivors\n")
  end

  it "refuses to overwrite with exit 2 naming the path, and keeps the file" do
    FileUtils.mkdir_p(File.join(@dir, "config"))
    path = File.join(@dir, "config", "saboteur.rb")
    File.write(path, "# mine\n")
    expect(run_init(@dir)).to eq(2)
    expect(err.string).to include("config/saboteur.rb already exists", path)
    expect(File.read(path)).to eq("# mine\n")
  end

  it "overwrites under --force" do
    FileUtils.mkdir_p(File.join(@dir, "config"))
    File.write(File.join(@dir, "config", "saboteur.rb"), "# mine\n")
    expect(run_init(@dir, "--force")).to eq(0)
    expect(File.read(File.join(@dir, "config", "saboteur.rb"))).to eq(Saboteur::StarterConfig::TEXT)
  end

  it "rejects stray arguments" do
    expect(run_init(@dir, "extra")).to eq(2)
  end
end
