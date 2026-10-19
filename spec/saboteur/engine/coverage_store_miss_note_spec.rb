# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "fileutils"
require "timeout"
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
    expect(Dir[File.join(@root, ".saboteur", "inputs-*.json")].size).to eq(1)

    File.write(file, "2\n")
    second, second_err = noisy_store
    second.fetch([file])
    expect(second_err.string).to include("changed since the last map: 1 edited (a.rb);")
  end

  it "hashes every file under spec/ in the snapshot, fixtures included, but never the cache dir (#46)" do
    FileUtils.mkdir_p(File.join(@root, "spec", "fixtures", "deep"))
    File.write(File.join(@root, "spec", "fixtures", "deep", "data.yml"), "a: 1\n")
    File.write(File.join(@root, "spec", ".hidden.txt"), "h\n")
    FileUtils.mkdir_p(File.join(@root, "spec", ".cache"))
    FileUtils.mkdir_p(File.join(@root, "spec", ".cache-two"))
    File.write(File.join(@root, "spec", ".cache-two", "sibling.txt"), "s\n")
    File.write(File.join(@root, "spec", ".cache", "stray.json"), "{}")
    store, = noisy_store(cache_dir: "spec/.cache")
    store.fetch([file])

    snapshot = Saboteur::Engine::CoverageInputsSnapshot.latest(File.join(@root, "spec", ".cache"), @root)
    names = snapshot.fetch("files").keys
    expect(names).to include("spec/fixtures/deep/data.yml", "spec/.hidden.txt", "spec/.cache-two/sibling.txt")
    expect(names).not_to include("spec/fixtures", "spec/fixtures/deep")
    expect(names.grep(%r{\Aspec/\.cache/})).to eq([])
  end

  it "leaves RSpec's generated spec/examples.txt out of the snapshot, so rewriting it is no change (#46)" do
    File.write(File.join(@root, "spec", "examples.txt"), "run 1\n") if FileUtils.mkdir_p(File.join(@root, "spec"))
    File.write(File.join(@root, "spec", "examples_helper.txt"), "kept\n")
    store, = noisy_store
    store.fetch([file])

    names = Saboteur::Engine::CoverageInputsSnapshot.latest(File.join(@root, ".saboteur"), @root).fetch("files").keys
    expect(names).to include("spec/examples_helper.txt")
    expect(names).not_to include("spec/examples.txt")
  end

  it "lists a symlink or a FIFO under spec/ without ever reading it, so the pair can never be reused partially (#46)" do
    FileUtils.mkdir_p(File.join(@root, "spec", "fixtures"))
    File.symlink("/dev/zero", File.join(@root, "spec", "fixtures", "link"))
    File.symlink("/etc", File.join(@root, "spec", "fixtures", "dirlink"))
    system("mkfifo", File.join(@root, "spec", "fixtures", "pipe"), exception: true)
    store, = noisy_store
    Timeout.timeout(5) { store.fetch([file]) }

    files = Saboteur::Engine::CoverageInputsSnapshot.latest(File.join(@root, ".saboteur"), @root).fetch("files")
    expect(files.slice("spec/fixtures/link", "spec/fixtures/dirlink", "spec/fixtures/pipe").values).to eq([false] * 3)
  end

  it "records the seed the map is built with, and hashes the suite's own test directory, not only spec/ (#46)" do
    FileUtils.mkdir_p(File.join(@root, "test", "fixtures"))
    File.write(File.join(@root, "test", "fixtures", "d.yml"), "a: 1\n")
    FileUtils.mkdir_p(File.join(@root, "te[s]t*"))
    File.write(File.join(@root, "te[s]t*", "b_test.rb"), "1\n")
    File.write(File.join(@root, "te[s]t*", "rows.json"), "[]\n")
    FileUtils.mkdir_p(File.join(@root, "tesst"))
    File.write(File.join(@root, "tesst", "other.json"), "[]\n")
    FileUtils.mkdir_p(File.join(@root, "test", "data"))
    File.write(File.join(@root, "test", "data", "rows.json"), "[]\n")
    File.write(File.join(@root, "test", "a_test.rb"), "1\n")
    File.write(File.join(@root, "top_spec.rb"), "1\n")
    File.write(File.join(@root, "stray.txt"), "not a test input\n")
    allow(integration).to receive(:test_files).and_return(
      [File.join(@root, "test", "a_test.rb"), File.join(@root, "top_spec.rb"), "/elsewhere/x_spec.rb",
       File.join(@root, "te[s]t*", "b_test.rb")]
    )
    store, = noisy_store(seed: 7)
    store.fetch([file])

    snapshot = Saboteur::Engine::CoverageInputsSnapshot.latest(File.join(@root, ".saboteur"), @root)
    expect(snapshot["seed"]).to eq(7)
    expect(snapshot["files"].keys).to include("test/data/rows.json", "test/a_test.rb", "top_spec.rb")
    expect(snapshot["files"].keys).to include("te[s]t*/rows.json")
    expect(snapshot["files"].keys).not_to include("test/fixtures", "stray.txt", "tesst/other.json")
    expect(snapshot["files"].keys.grep(%r{\A/})).to eq(["/elsewhere/x_spec.rb"])
    expect(snapshot["files"].fetch("(test file outside the project root)")).to be(false)
  end

  it "hashes the test directory of a test file spelled through a symlinked root (#46)" do
    FileUtils.mkdir_p(File.join(@root, "test", "data"))
    File.write(File.join(@root, "test", "data", "rows.json"), "[]\n")
    File.write(File.join(@root, "test", "a_test.rb"), "1\n")
    link = "#{@root}-link"
    File.symlink(@root, link)
    allow(integration).to receive(:test_files).and_return([File.join(link, "test", "a_test.rb")])
    config = Saboteur::Config.new({}, root: link)
    linked = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                 supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new))
    allow(linked).to receive(:build).and_return(map)
    linked.fetch([file])

    names = Saboteur::Engine::CoverageInputsSnapshot.latest(File.join(@root, ".saboteur"), @root).fetch("files").keys
    expect(names).to include("test/data/rows.json")
    expect(names).not_to include("(test file outside the project root)")
  ensure
    FileUtils.rm_f(link) if link
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
    path = Dir[File.join(@root, ".saboteur", "inputs-*.json")].fetch(0)
    data = JSON.parse(File.read(path))
    data["files"]["a\n::error::boom ##[warning]x\e[31m"] = "f" * 64
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

    expect(err.string).to include("coverage cache miss: settings, Ruby or saboteur version changed;")
  end

  it "says settings changed when only the saboteur version changes" do
    first, = noisy_store
    first.fetch([file])
    stub_const("Saboteur::VERSION", "#{Saboteur::VERSION}.next")
    later, err = noisy_store
    later.fetch([file])

    expect(err.string).to include("coverage cache miss: settings, Ruby or saboteur version changed;")
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
