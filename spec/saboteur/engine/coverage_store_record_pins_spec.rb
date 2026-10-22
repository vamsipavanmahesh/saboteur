# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine::CoverageStore, "pins" do
  def build_store(root, integration: nil, hooks: Saboteur::Hooks.new, **settings)
    config = Saboteur::Config.new(settings, root: root)
    integration ||= instance_double(Saboteur::Integration::RSpec, test_files: [], run_all: true)
    described_class.new(config: config, integration: integration, hooks: hooks, supervisor: nil, diagnostics: nil)
  end

  describe "#build" do
    it "refuses to build when Coverage is not suspended, and says what state it is in" do
      Dir.mktmpdir do |root|
        allow(Coverage).to receive(:state).and_return(:running)
        expect { build_store(root).send(:build, []) }.to raise_error(
          Saboteur::Error,
          "Coverage is running; saboteur must set it up before the app loads. " \
          "Run through the saboteur executable and disable SimpleCov for the run."
        )
      end
    end

    it "refuses to build when Coverage cannot report a state at all" do
      Dir.mktmpdir do |root|
        allow(Coverage).to receive(:respond_to?).and_call_original
        allow(Coverage).to receive(:respond_to?).with(:state).and_return(false)
        allow(Coverage).to receive(:state).and_return(:suspended)
        expect { build_store(root).send(:build, []) }.to raise_error(Saboteur::Error, /\ACoverage is suspended;/)
      end
    end
  end

  describe "#real_directory?" do
    it "treats a path that vanished as a directory, so it is skipped" do
      Dir.mktmpdir do |root|
        store = build_store(root)
        expect(store.send(:real_directory?, File.join(root, "gone"))).to be(true)
        expect(store.send(:real_directory?, root)).to be(true)
        File.write(File.join(root, "a.rb"), "1\n")
        expect(store.send(:real_directory?, File.join(root, "a.rb"))).to be(false)
      end
    end
  end

  describe "#raise_budget_stop" do
    it "names the admitted seconds and the configured phase timeout" do
      Dir.mktmpdir do |root|
        store = build_store(root, "coverage_timeout" => 600)
        expect { store.send(:raise_budget_stop, 12.34) }.to raise_error(
          Saboteur::BudgetPhaseTimeout,
          "the --max-duration budget stopped the coverage map build (admitted 12.3s of the 600.0s phase timeout)"
        )
      end
    end
  end

  describe "#record" do
    let(:recorder) { instance_double(Saboteur::Selection::Recorder, start: nil) }

    before do
      allow(Saboteur::Selection::Recorder).to receive(:new).and_return(recorder)
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow($stdout).to receive(:sync=)
    end

    it "flushes the suite log, merges stderr into it, runs the after_fork hook and starts the recorder" do
      Dir.mktmpdir do |root|
        hooks = instance_double(Saboteur::Hooks, run: nil)
        store = build_store(root, hooks: hooks)
        allow(store).to receive(:write_map)
        store.send(:record, StringIO.new, ["/root/lib/a.rb"])
        expect($stdout).to have_received(:sync=).with(true)
        expect($stderr).to have_received(:reopen).with($stdout)
        expect(hooks).to have_received(:run).with(:after_fork)
        expect(recorder).to have_received(:start)
      end
    end

    it "reports the error class and message, then exits with status 1" do
      Dir.mktmpdir do |root|
        integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
        allow(integration).to receive(:run_all).and_raise(ArgumentError, "boom")
        store = build_store(root, integration: integration)
        allow(store).to receive(:exit!)
        writer = StringIO.new
        store.send(:record, writer, ["/root/lib/a.rb"])
        expect(JSON.parse(writer.string)).to eq("error" => "ArgumentError: boom")
        expect(store).to have_received(:exit!).with(1)
      end
    end
  end
  # Review C1: only a whole-suite run's map is worth remembering for later
  # scoped runs; the pointer names the map's cache key.
  describe "#record_whole_suite_map (review C1)" do
    def whole_suite_store(root, whole_suite_run: true)
      config = Saboteur::Config.new({ "cache" => true }, root: root)
      described_class.new(config: config, integration: instance_double(Saboteur::Integration::RSpec),
                          hooks: Saboteur::Hooks.new, supervisor: nil, diagnostics: nil, whole_suite_run:)
    end

    it "writes the whole-suite pointer when a whole-suite build persists its map" do
      Dir.mktmpdir do |root|
        store = whole_suite_store(root)
        map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
        store.send(:persist_map, File.join(root, ".saboteur", "coverage-deadbeef.json"), map)

        pointer = File.join(root, ".saboteur", "whole-suite-map-v2")
        expect(File.read(pointer)).to eq("deadbeef")
        expect(File.stat(pointer).mode & 0o777).to eq(0o600)
        expect(store.fetched_map).to be(map)
      end
    end

    it "writes no pointer for a scoped run, but still adopts the persisted map" do
      Dir.mktmpdir do |root|
        store = whole_suite_store(root, whole_suite_run: false)
        map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
        store.send(:persist_map, File.join(root, ".saboteur", "coverage-deadbeef.json"), map)

        expect(File.exist?(File.join(root, ".saboteur", "whole-suite-map-v2"))).to be(false)
        expect(store.fetched_map).to be(map)
      end
    end

    # A mutant that drops the cache-dir join writes the pointer into the
    # cwd instead; a green run must leave nothing there (review C1).
    it "leaves no whole-suite pointer at the repository root" do
      expect(File.file?(described_class::WHOLE_SUITE_POINTER)).to be(false)
    end

    it "records the pointer when serving a cached map on a whole-suite run" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, ".saboteur"))
        store = whole_suite_store(root)
        cached = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
        store.send(:serve_cached, File.join(root, ".saboteur", "coverage-cafe.json"), cached, [], [])

        pointer = File.join(root, ".saboteur", "whole-suite-map-v2")
        expect(File.read(pointer)).to eq("cafe")
        expect(File.stat(pointer).mode & 0o777).to eq(0o600)
        expect(store.fetched_map).not_to be_nil
      end
    end
  end

  # The later scoped run reads the pointer a whole-suite build left: nil for
  # every way the pointer can be missing, stale, or unreadable (review C1).
  describe "#whole_suite_map (review C1)" do
    def cached_store(root, cache: true)
      config = Saboteur::Config.new({ "cache" => cache }, root: root)
      described_class.new(config: config, integration: instance_double(Saboteur::Integration::RSpec),
                          hooks: Saboteur::Hooks.new, supervisor: nil, diagnostics: nil)
    end

    def write_pointer(root, content, mode: 0o600)
      pointer = File.join(root, ".saboteur", "whole-suite-map-v2")
      FileUtils.mkdir_p(File.dirname(pointer))
      File.write(pointer, content)
      File.chmod(mode, pointer)
      pointer
    end

    it "is nil when caching is off" do
      Dir.mktmpdir do |root|
        write_pointer(root, "a" * 64)
        expect(cached_store(root, cache: false).whole_suite_map).to be_nil
      end
    end

    it "is nil when no pointer exists" do
      Dir.mktmpdir do |root|
        expect(cached_store(root).whole_suite_map).to be_nil
      end
    end

    it "is nil when the pointer holds garbage" do
      Dir.mktmpdir do |root|
        write_pointer(root, "not-a-cache-key\n")
        expect(cached_store(root).whole_suite_map).to be_nil
      end
    end

    it "is nil when the pointer names a map that is no longer cached" do
      Dir.mktmpdir do |root|
        write_pointer(root, "a" * 64)
        expect(cached_store(root).whole_suite_map).to be_nil
      end
    end

    it "is nil when the pointer cannot be read" do
      Dir.mktmpdir do |root|
        write_pointer(root, "a" * 64, mode: 0o000)
        expect(cached_store(root).whole_suite_map).to be_nil
      end
    end

    # A cached map plus a pointer naming it. The map is filed under the
    # pointer's exact content, so a key check that accepts too much would
    # still find a map to serve.
    def record_whole_suite(root, content)
      writer = cached_store(root)
      map = Saboteur::Selection::CoverageMap.new(lines: { "a.rb" => { 1 => ["t1"] } }, tests: ["t1"])
      writer.send(:persist_map, File.join(root, ".saboteur", "coverage-#{content}.json"), map)
      write_pointer(root, "#{content}\n")
    end

    it "loads the map a whole-suite build recorded" do
      Dir.mktmpdir do |root|
        record_whole_suite(root, "b" * 64)
        expect(cached_store(root).whole_suite_map.tests).to eq(["t1"])
      end
    end

    it "ignores a recorded whole-suite map while caching is off" do
      Dir.mktmpdir do |root|
        record_whole_suite(root, "b" * 64)
        expect(cached_store(root, cache: false).whole_suite_map).to be_nil
      end
    end

    it "returns nil without reading a pointer that is not there" do
      Dir.mktmpdir do |root|
        allow(File).to receive(:read).and_raise(RuntimeError, "no pointer read expected")
        expect(cached_store(root).whole_suite_map).to be_nil
      end
    end

    it "reads the pointer as UTF-8" do
      Dir.mktmpdir do |root|
        record_whole_suite(root, "b" * 64)
        allow(File).to receive(:read).and_call_original

        expect(cached_store(root).whole_suite_map).not_to be_nil
        pointer = File.join(root, ".saboteur", "whole-suite-map-v2")
        expect(File).to have_received(:read).with(pointer, encoding: Encoding::UTF_8)
      end
    end

    it "ignores a recorded map whose key is not hex" do
      Dir.mktmpdir do |root|
        record_whole_suite(root, "not-a-cache-key")
        expect(cached_store(root).whole_suite_map).to be_nil
      end
    end

    it "ignores a pointer whose key trails stray bytes" do
      Dir.mktmpdir do |root|
        record_whole_suite(root, "zz#{'b' * 64}")
        expect(cached_store(root).whole_suite_map).to be_nil
      end
    end

    it "ignores a pointer whose key is followed by stray bytes" do
      Dir.mktmpdir do |root|
        record_whole_suite(root, "#{'b' * 64}zz")
        expect(cached_store(root).whole_suite_map).to be_nil
      end
    end
  end
end
