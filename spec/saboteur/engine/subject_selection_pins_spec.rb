# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine::SubjectSelection, "pins" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }

  def commit_base(name, text)
    file = File.join(@root, name)
    File.write(file, text)
    [%w[init -q], %w[add .], %w[commit -q -m base]].each do |args|
      Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
    end
    file
  end

  def select(files, **settings)
    config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)
    described_class.new(config, diagnostics).select(files)
  end

  it "hands the project root to the custom map loader" do
    allow(Saboteur::CustomMap).to receive(:load).and_call_original
    described_class.new(Saboteur::Config.new({}, root: @root), diagnostics)
    expect(Saboteur::CustomMap).to have_received(:load).with(anything, root: @root)
  end

  it "matches a constant subject by an enclosing module name when --since is set" do
    file = File.join(@root, "shop.rb")
    File.write(file, "module Shop\n  LIMITS = { a: 1 }.freeze\nend\n")
    expect(described_class.files_matching(@root, [file], ["Shop"], { "since" => "HEAD" })).to eq(["shop.rb"])
    expect(described_class.files_matching(@root, [file], ["Shop::LIM"], { "since" => "HEAD" })).to eq([])
  end

  it "admits a constant through a whole_file glob, and does not call a matching glob unmatched" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\nvalidate!(RULES)\n")
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n  b: 2"))
    expect(select([file], since: "HEAD", whole_file: ["RU*"]).map(&:id)).to eq(["RULES"])
    expect(diagnostics.warnings.join).not_to include("fix the whole_file entry")
  end

  it "does not match a whole_file entry that only looks like a glob of the subject id" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\nvalidate!(RULES)\n")
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n  b: 2"))
    expect(select([file], since: "HEAD", whole_file: ["R"]).map(&:id)).to eq([])
    expect(diagnostics.warnings.join).to include('fix the whole_file entry "R"')
  end
end
