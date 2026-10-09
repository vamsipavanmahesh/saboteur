# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "fileutils"
require "tmpdir"

RSpec.describe Saboteur::Engine::CoverageStore do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:file) { File.join(@root, "a.rb").tap { |path| File.write(path, "1\n") } }
  let(:integration) { instance_double(Saboteur::Integration::RSpec, test_files: []) }
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }
  let(:map) { Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"]) }

  def store(**settings)
    config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new))
  end

  def cache_files
    Dir[File.join(@root, ".saboteur", "coverage-*.json")]
  end

  it "builds once, saves, and reuses the cached map while inputs are unchanged" do
    first = store
    allow(first).to receive(:build).and_return(map)
    expect(first.fetch([file]).tests).to eq(["t1"])
    expect(cache_files.size).to eq(1)

    second = store
    allow(second).to receive(:build)
    expect(second.fetch([file]).tests).to eq(["t1"])
    expect(second).not_to have_received(:build)
  end

  it "rebuilds when a source file changes" do
    first = store
    allow(first).to receive(:build).and_return(map)
    first.fetch([file])
    File.write(file, "2\n")
    second = store
    allow(second).to receive(:build).and_return(map)
    second.fetch([file])
    expect(second).to have_received(:build)
    expect(cache_files.size).to eq(2)
  end

  # Support files, spec_helper and boot files decide which test runs which
  # line just as much as example files do.
  ["spec/support/helpers.rb", "spec/spec_helper.rb", ".rspec", "config/boot.rb", "config/saboteur_hooks.rb"]
    .each do |input|
      it "rebuilds when #{input} changes" do
        path = File.join(@root, input)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "1\n")
        settings = { "config/boot.rb" => { require: ["./config/boot"] },
                     "config/saboteur_hooks.rb" => { hooks: ["config/saboteur_hooks.rb"] } }.fetch(input, {})
        first = store(**settings)
        allow(first).to receive(:build).and_return(map)
        first.fetch([file])
        File.write(path, "2\n")
        second = store(**settings)
        allow(second).to receive(:build).and_return(map)
        second.fetch([file])
        expect(second).to have_received(:build)
      end
    end

  it "ignores the cache when caching is off" do
    store.tap { |s| allow(s).to receive(:build).and_return(map) }.fetch([file])
    uncached = store(cache: false)
    allow(uncached).to receive(:build).and_return(map)
    uncached.fetch([file])
    expect(uncached).to have_received(:build)
  end
end
