# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "fileutils"
require "tmpdir"

RSpec.describe Saboteur::Engine::CoverageStore, "cache-miss note (#46)" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  before { allow(Saboteur::CoverageReads).to receive(:result).and_return({}) }

  let(:file) { File.join(@root, "a.rb").tap { |path| File.write(path, "1\n") } }
  let(:integration) { instance_double(Saboteur::Integration::RSpec, test_files: []) }
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }
  let(:map) { Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"]) }

  def noisy_store(**settings)
    err = StringIO.new
    config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)
    store = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(err))
    allow(store).to receive(:build).and_return(map)
    [store, err]
  end

  it "explains the first miss, saves the input snapshot, then names the changed file on the next miss" do
    first, first_err = noisy_store
    first.fetch([file])
    expect(first_err.string).to include("saboteur: coverage cache miss: no earlier map to compare with;")
    expect(File.exist?(File.join(@root, ".saboteur", "inputs-coverage.json"))).to be(true)

    File.write(file, "2\n")
    second, second_err = noisy_store
    second.fetch([file])
    expect(second_err.string).to include("changed since the last map: 1 edited (a.rb);")
  end

  it "stays silent on a cache hit" do
    first, = noisy_store
    first.fetch([file])
    second, err = noisy_store
    second.fetch([file])

    expect(err.string).not_to include("coverage cache miss")
  end

  it "stays silent when --no-cache asked for the rebuild" do
    uncached, err = noisy_store(cache: false)
    uncached.fetch([file])

    expect(err.string).not_to include("coverage cache miss")
  end

  it "says the build is scoped when --test selected the specs" do
    scoped, err = noisy_store(tests: ["spec/one_spec.rb"])
    scoped.fetch([file])

    expect(err.string).to include("the map build runs the selected specs once\n")
  end

  def line_starts_command?(text)
    text.lines.any? { |line| line.sub(/\A[[:space:]]*/, "").start_with?("::") || line.include?("##[") }
  end

  it "cannot be used to forge runner commands through a hostile file name" do
    hostile = File.join(@root, "x\n::error::pwned.rb")
    File.write(hostile, "1\n")
    mid = File.join(@root, "y ##[error]z.rb")
    File.write(mid, "1\n")
    first, = noisy_store
    allow(first).to receive(:build).and_return(map)
    first.fetch([file, hostile, mid])
    File.write(hostile, "2\n")
    File.write(mid, "2\n")
    second, err = noisy_store
    allow(second).to receive(:build).and_return(map)
    second.fetch([file, hostile, mid])

    expect(err.string).to include("2 edited").and include("x\\x0a::error::pwned.rb").and include("y ##\\x5berror]z.rb")
    expect(line_starts_command?(err.string.sub("saboteur: ", ""))).to be(false)
    expect(err.string).not_to include("##[")
  end

  it "cannot be used to forge runner commands through a hostile key in a restored snapshot" do
    first, = noisy_store
    allow(first).to receive(:build).and_return(map)
    first.fetch([file])
    path = File.join(@root, ".saboteur", "inputs-coverage.json")
    data = JSON.parse(File.read(path))
    data["files"]["a\n::error::boom ##[warning]x\e[31m"] = "digest"
    File.write(path, JSON.generate(data))
    File.write(file, "2\n")
    second, err = noisy_store
    allow(second).to receive(:build).and_return(map)
    second.fetch([file])

    expect(err.string).to include("1 edited, 1 removed")
    expect(err.string).to include("a\\x0a::error::boom ##\\x5bwarning]x,")
    expect(line_starts_command?(err.string.sub("saboteur: ", ""))).to be(false)
  end

  it "keeps a run going when the snapshot cannot be written" do
    blocked, err = noisy_store
    allow(File).to receive(:rename).and_call_original
    allow(File).to receive(:rename).with(/inputs-coverage\.json\.\d+\.tmp/, anything).and_raise(Errno::EACCES)

    expect(blocked.fetch([file]).tests).to eq(["t1"])
    expect(err.string).to include("coverage cache miss")
  end

  it "says settings changed, not files, when a cache-key config input changes" do
    first, = noisy_store
    first.fetch([file])
    changed, err = noisy_store(rspec_args: ["--tag", "fast"])
    changed.fetch([file])

    expect(err.string).to include("coverage cache miss: settings or saboteur version changed;")
  end

  it "says settings changed when only the saboteur version changes" do
    first, = noisy_store
    first.fetch([file])
    stub_const("Saboteur::VERSION", "#{Saboteur::VERSION}.next")
    later, err = noisy_store
    later.fetch([file])

    expect(err.string).to include("coverage cache miss: settings or saboteur version changed;")
  end

  describe "the cache key's file list" do
    it "is the files, the integration's test files, the suite files and the lockfile, each once, in that order" do
      spec_file = File.join(@root, "spec", "a_spec.rb")
      FileUtils.mkdir_p(File.dirname(spec_file))
      File.write(spec_file, "# spec\n")
      File.write(File.join(@root, "Gemfile.lock"), "lock\n")
      helper = File.join(@root, "spec", "spec_helper.rb")
      File.write(helper, "# helper\n")
      allow(integration).to receive(:test_files).and_return([spec_file, file])
      store, = noisy_store
      suite = instance_double(Saboteur::Engine::SuiteFiles, files: [helper, file])
      allow(Saboteur::Engine::SuiteFiles).to receive(:new).and_return(suite)

      expect(store.send(:key_files, [file])).to eq([file, spec_file, helper, File.join(@root, "Gemfile.lock")])
    end

    it "changes the cache key when a test file or a lockfile appears" do
      store, = noisy_store
      before = store.send(:cache_key, [file])
      allow(integration).to receive(:test_files).and_return([File.join(@root, "spec", "b_spec.rb")])
      expect(store.send(:cache_key, [file])).not_to eq(before)
    end
  end
end
