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

  it "rebuilds when the lockfile changes" do
    lock = File.join(@root, "Gemfile.lock").tap { |p| File.write(p, "a\n") }
    store.tap { |s| allow(s).to receive(:build).and_return(map) }.fetch([file])
    File.write(lock, "b\n")
    again = store
    allow(again).to receive(:build).and_return(map)
    again.fetch([file])
    expect(again).to have_received(:build)
  end

  it "builds the map in a supervised child and says so" do
    err = StringIO.new
    built = Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"])
    result = Saboteur::Execution::Supervisor::Result.new(payload: built.to_json, exit_status: nil, stopped_by: nil,
                                                         detail: nil, runtime: 1.0, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(result)
    allow(Coverage).to receive(:state).and_return(:suspended)
    diagnostics = Saboteur::Engine::Diagnostics.new(err)
    allow(diagnostics).to receive(:progress_heartbeat).and_call_original
    store = described_class.new(config: Saboteur::Config.new({}, root: @root), integration: integration,
                                hooks: Saboteur::Hooks.new, supervisor: supervisor,
                                diagnostics: diagnostics)
    expect(store.fetch([file]).tests).to eq(["t1"])
    expect(err.string).to include("building coverage map (runs the whole suite once)")
    expect(diagnostics).to have_received(:progress_heartbeat).with("building coverage map")
    expect(supervisor).to have_received(:run).with(timeout: 3600.0, on_tick: anything)
  end

  # --test narrows the map build to the given specs; the message must say
  # so, or a user waits for the whole suite without knowing.
  it "says the map build runs only the selected specs when --test narrowed the suite" do
    err = StringIO.new
    built = Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"])
    result = Saboteur::Execution::Supervisor::Result.new(payload: built.to_json, exit_status: nil, stopped_by: nil,
                                                         detail: nil, runtime: 1.0, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(result)
    allow(Coverage).to receive(:state).and_return(:suspended)
    store = described_class.new(config: Saboteur::Config.new({ "tests" => ["spec/one_spec.rb"] }, root: @root),
                                integration: integration, hooks: Saboteur::Hooks.new, supervisor: supervisor,
                                diagnostics: Saboteur::Engine::Diagnostics.new(err))
    store.fetch([file])
    expect(err.string).to include("building coverage map (runs the selected specs once)")
  end

  # A child that dies before reporting (a crash in a native extension, an
  # exit! in the suite) must leave enough to find out why.
  [[{ signaled?: true, termsig: 11 }, "was killed by signal SEGV"],
   [{ signaled?: false, exitstatus: 2 }, "exited with status 2"]].each do |status, how|
    it "says how the coverage child ended when it #{how} without a result" do
      died = Saboteur::Execution::Supervisor::Result.new(
        payload: "", exit_status: instance_double(Process::Status, **status), stopped_by: nil,
        detail: nil, runtime: 1.0, leftover_pids: []
      )
      allow(supervisor).to receive(:run).and_return(died)
      allow(Coverage).to receive(:state).and_return(:suspended)
      expect { store.fetch([file]) }.to raise_error(
        Saboteur::Error, "coverage map build failed: the suite #{how} before reporting; " \
                         "its output is in .saboteur/coverage-build.log"
      )
    end
  end

  it "refuses to build when Coverage was not set up by the executable" do
    allow(Coverage).to receive(:state).and_return(:idle)
    expect { store.fetch([file]) }.to raise_error(Saboteur::Error, /SimpleCov/)
  end

  it "ignores the cache when caching is off" do
    store.tap { |s| allow(s).to receive(:build).and_return(map) }.fetch([file])
    uncached = store(cache: false)
    allow(uncached).to receive(:build).and_return(map)
    uncached.fetch([file])
    expect(uncached).to have_received(:build)
  end
end

RSpec.describe Saboteur::Engine::CoverageStore, "heap preparation" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:file) { File.join(@root, "a.rb").tap { |path| File.write(path, "1\n") } }
  let(:integration) { instance_double(Saboteur::Integration::RSpec, test_files: []) }
  let(:map) { Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => ["t1"] } }, tests: ["t1"]) }

  def store(supervisor)
    config = Saboteur::Config.new({ "coverage_timeout" => 60 }, root: @root)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new))
  end

  def recording_supervisor(events, payload)
    Class.new do
      define_method(:run) do |**|
        events << :fork
        Saboteur::Execution::Supervisor::Result.new(payload: payload, exit_status: nil, stopped_by: nil,
                                                    detail: nil, runtime: 0.0, leftover_pids: [])
      end
    end.new
  end

  # The coverage child inherits the parent's heap, so the store must prepare
  # that heap before the fork, not after.
  it "prepares the heap once, before forking the coverage child" do
    events = []
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap) { events << :prepare }
    # fetch's coverage guard expects the saboteur executable's setup.
    allow(Coverage).to receive(:state).and_return(:suspended)
    store(recording_supervisor(events, map.to_json)).fetch([file])
    expect(events).to eq(%i[prepare fork])
  end

  # A cached map means no child forks, so there is nothing to prepare for.
  it "does not prepare on a cache hit" do
    allow(Coverage).to receive(:state).and_return(:suspended)
    events = []
    store(recording_supervisor(events, map.to_json)).fetch([file])
    events.clear
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap) { events << :prepare }
    store(recording_supervisor(events, map.to_json)).fetch([file])
    expect(events).to be_empty
  end
  # A run that cannot build coverage must fail before any preparation.
  it "does not prepare when the coverage precondition is unmet" do
    allow(Coverage).to receive(:state).and_return(:running)
    events = []
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap) { events << :prepare }
    expect { store(recording_supervisor(events, map.to_json)).fetch([file]) }
      .to raise_error(Saboteur::Error, /must set it up/)
    expect(events).to be_empty
  end
end

RSpec.describe Saboteur::Engine::CoverageStore, "suite return validation" do
  it "does not produce a coverage payload when the unchanged adapter reports failure" do
    Dir.mktmpdir do |root|
      config = Saboteur::Config.new({}, root: root)
      integration = instance_double(Saboteur::Integration::RSpec)
      expect(integration).to receive(:run_all).and_return(false)
      writer = StringIO.new
      recorder = instance_double(Saboteur::Selection::Recorder, start: nil)
      allow(Saboteur::Selection::Recorder).to receive(:new).and_return(recorder)
      store = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                  supervisor: nil, diagnostics: nil)
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(store).to receive(:exit!)
      store.send(:record, writer, [])
      expect(JSON.parse(writer.string)["error"]).to include("unchanged suite failed", "seed 1")
    end
  end
end

RSpec.describe Saboteur::Engine::CoverageStore, "successful recording" do
  it "writes a map after a green suite and does not lose the adapter return" do
    Dir.mktmpdir do |root|
      config = Saboteur::Config.new({}, root: root)
      integration = instance_double(Saboteur::Integration::RSpec, run_all: true)
      recorder = instance_double(Saboteur::Selection::Recorder, start: nil)
      map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: ["t1"])
      allow(recorder).to receive(:result).and_return(map)
      allow(Saboteur::Selection::Recorder).to receive(:new).and_return(recorder)
      store = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                  supervisor: nil, diagnostics: nil)
      writer = StringIO.new
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      store.send(:record, writer, [])
      expect(JSON.parse(writer.string)["tests"]).to eq(["t1"])
    end
  end
end
