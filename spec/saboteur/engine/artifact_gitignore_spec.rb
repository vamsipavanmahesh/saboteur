# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# A run's artifacts ignore themselves (#426): without the marker, a
# `git add -A` in the target project commits logs, coverage maps and
# reports. The pattern is the one git, vagrant and bundler use.
RSpec.describe Saboteur::Engine, "self-ignoring artifact dir (#426)" do
  around do |example|
    Dir.mktmpdir { |dir| @root = File.realpath(dir) and example.run }
  end

  def engine(settings = {})
    described_class.new(Saboteur::Config.new(settings, root: @root), err: StringIO.new)
  end

  it "writes a star .gitignore into the artifact dir" do
    engine.send(:ensure_artifacts_self_ignored)
    marker = File.join(@root, ".saboteur", ".gitignore")
    expect(File.read(marker)).to eq("*\n")
  end

  it "keeps a .gitignore the user wrote" do
    dir = File.join(@root, ".saboteur")
    FileUtils.mkdir_p(dir)
    marker = File.join(dir, ".gitignore")
    File.write(marker, "report.html\n")
    engine.send(:ensure_artifacts_self_ignored)
    expect(File.read(marker)).to eq("report.html\n")
  end

  it "honours a custom cache_dir" do
    engine({ "cache_dir" => "tmp/sab" }).send(:ensure_artifacts_self_ignored)
    expect(File.read(File.join(@root, "tmp", "sab", ".gitignore"))).to eq("*\n")
  end
  it "self-ignores the artifact dir from Engine#call itself (#426 call site)" do
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    eng = engine
    expect(eng).to receive(:ensure_artifacts_self_ignored).and_call_original
    # Stop the run right after the call site; later stages need a full project.
    allow(eng).to receive(:monotonic).and_raise(StandardError, "stop after self-ignore")
    expect { eng.call }.to raise_error(StandardError, "stop after self-ignore")
    expect(File.read(File.join(@root, ".saboteur", ".gitignore"))).to eq("*\n")
  end
end
