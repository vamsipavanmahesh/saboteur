# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "boot coverage lines" do
  # An isolated root, never the ambient cwd: the engine.call test reaches
  # scheduler_for, whose fresh_log_dir wipes <root>/.saboteur/logs - under an
  # enclosing saboteur run a cwd-rooted engine deletes the outer run's logs.
  let(:root) { Dir.mktmpdir("saboteur-load-lines-") }
  let(:engine) { described_class.new(Saboteur::Config.new({ "all" => true }, root: root), err: StringIO.new) }

  after { FileUtils.rm_rf(root) }
  let(:fake_coverage) { Module.new }

  before do
    allow(fake_coverage).to receive(:state).and_return(:suspended)
    allow(fake_coverage).to receive(:result).with(stop: false, clear: false).and_return({})
    stub_const("Coverage", fake_coverage)
  end

  it "keeps only positive counters for included files" do
    file = File.realpath(__FILE__)
    allow(fake_coverage).to receive(:result).and_return(
      file => { lines: [nil, 0, 2, 1] }, "/outside.rb" => { lines: [1] }
    )
    expect(Saboteur::Engine::LoadCoverage.capture([file])).to eq([{ file => [3, 4] }, {}])
    expect(Saboteur::Engine::LoadCoverage.capture([])).to eq([{}, {}])
  end

  it "omits files with no load hits and returns empty outside suspended coverage" do
    file = File.realpath(__FILE__)
    allow(fake_coverage).to receive(:result).and_return(file => { lines: [nil, 0] })
    expect(Saboteur::Engine::LoadCoverage.capture([file])).to eq([{}, {}])
    allow(fake_coverage).to receive(:state).and_return(:running)
    expect(Saboteur::Engine::LoadCoverage.capture([file])).to eq([{}, {}])
  end

  it "suspends running coverage before capturing the counters" do
    allow(fake_coverage).to receive(:state).and_return(:running, :suspended, :suspended, :suspended)
    expect(fake_coverage).to receive(:suspend).ordered
    expect(fake_coverage).to receive(:result).with(stop: false, clear: false).ordered.and_return({})
    expect(engine.send(:suspend_coverage, [])).to eq([{}, {}])
  end

  it "does not suspend already suspended coverage" do
    expect(fake_coverage).not_to receive(:suspend)
    expect(engine.send(:suspend_coverage, [])).to eq([{}, {}])
  end

  # A def-time macro's only caller runs while spec files load: the boot's
  # method counters name such defs so their mutants read as ran at load
  # instead of surviving on the pristine closure (#409).
  def boot_calls(hits)
    tracer = instance_double(Saboteur::MethodCalls, disable: nil, drain: hits)
    allow(Saboteur::MethodCalls).to receive(:booted).and_return(tracer)
  end

  def source_file(text)
    File.join(root, "defs.rb").tap { |path| File.write(path, text) }.then { |path| File.realpath(path) }
  end

  it "keeps the called methods' def lines for included files only" do
    file = File.realpath(__FILE__)
    boot_calls(file => Set[[3, :called]], "/outside.rb" => Set[[1, :x]])
    allow(fake_coverage).to receive(:result).and_return(file => { lines: [] }, "/outside.rb" => { lines: [] })
    expect(Saboteur::Engine::LoadCoverage.capture([file])).to eq([{}, { file => [3] }])
    expect(Saboteur::Engine::LoadCoverage.capture([])).to eq([{}, {}])
    allow(fake_coverage).to receive(:state).and_return(:running)
    expect(Saboteur::Engine::LoadCoverage.capture([file])).to eq([{}, {}])
  end

  it "dedupes a def line shared by two called one-line methods" do
    file = source_file("def one = 1; def two = 2\n")
    boot_calls(file => Set[[1, :one], [1, :two]])
    allow(fake_coverage).to receive(:result).and_return(file => { lines: [] })
    expect(Saboteur::Engine::LoadCoverage.capture([file])).to eq([{}, { file => [1] }])
  end

  it "reads no methods when the executable never armed the tracer" do
    file = File.realpath(__FILE__)
    allow(Saboteur::MethodCalls).to receive(:booted).and_return(nil)
    allow(fake_coverage).to receive(:result).and_return(file => { lines: [] })
    expect(Saboteur::Engine::LoadCoverage.capture([file])).to eq([{}, {}])
  end

  it "boots before selecting files and returns the captured load lines and methods" do
    boot = double("boot")
    integration = double("integration")
    expect(boot).to receive(:load_target).ordered.and_return(integration)
    expect(engine.config).to receive(:included_files).ordered.and_return(["a.rb"])
    expect(engine).to receive(:suspend_coverage).with(["a.rb"]).ordered.and_return([{ "a.rb" => [3] },
                                                                                    { "a.rb" => [2] }])
    expect(engine.send(:boot_target, boot)).to eq([integration, ["a.rb"], { "a.rb" => [3] }, { "a.rb" => [2] }])
  end
  it "does not read available counters while coverage is running" do
    file = File.realpath(__FILE__)
    allow(fake_coverage).to receive(:state).and_return(:running)
    allow(fake_coverage).to receive(:result).and_return(file => { lines: [1] })
    expect(fake_coverage).not_to receive(:result)
    expect(Saboteur::Engine::LoadCoverage.capture([file])).to eq([{}, {}])
  end
  it "passes the boot load lines and execution dependencies to the coverage store" do
    target = subjects_in("class WiringTarget\n  def value\n    1\n  end\nend\n").first
    integration = instance_double(Saboteur::Integration::RSpec, test_files: [], all_tests: [])
    boot = instance_double(Saboteur::Engine::Boot, rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    load_lines = { target.file => [3] }
    allow(engine).to receive(:boot_target).with(boot)
                                          .and_return([integration, [target.file], load_lines, {}])
    allow(engine).to receive(:select_subjects).with([target.file], test_files: []).and_return([[target], nil])
    allow(engine).to receive(:check_baseline).with(integration, 3)
    map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
    store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false, fetch: map)
    expect(Saboteur::Engine::CoverageStore).to receive(:new) do |config:, integration:, hooks:, load_lines:,
                                                              load_methods:, supervisor:, diagnostics:,
                                                              timeout_cap:, parts:, whole_suite_run:|
      expect(parts).to eq(1)
      expect(whole_suite_run).to be(true)
      expect(config).to equal(engine.config)
      expect(integration.test_files).to eq([])
      expect(hooks).to equal(engine.hooks)
      expect(load_lines).to eq(target.file => [3])
      expect(load_methods).to eq({})
      expect(timeout_cap).to respond_to(:call)
      expect(supervisor).to be_a(Saboteur::Execution::Supervisor)
      expect(supervisor.instance_variable_get(:@limits).max_memory_mb).to eq(8192)
      expect(diagnostics).to be_a(Saboteur::Engine::Diagnostics)
      store
    end
    allow(engine).to receive(:candidate_lists).and_return([[]])
    expect(engine.call.results).to eq([])
  end
  it "hands the configured coverage_parts to the coverage store (#741)" do
    parted = described_class.new(Saboteur::Config.new({ "all" => true, "coverage_parts" => 3 }, root: root),
                                 err: StringIO.new)
    expect(Saboteur::Engine::CoverageStore).to receive(:new).with(hash_including(parts: 3))

    parted.send(:coverage_store, instance_double(Saboteur::Integration::RSpec), {})
  end

  it "passes the boot load methods through mutate to the coverage store" do
    target = subjects_in("class WiringMethodsTarget\n  def value\n    1\n  end\nend\n").first
    integration = instance_double(Saboteur::Integration::RSpec, test_files: [], all_tests: [])
    boot = instance_double(Saboteur::Engine::Boot, rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    boot_methods = { target.file => [2] }
    allow(engine).to receive(:boot_target).with(boot)
                                          .and_return([integration, [target.file], {}, boot_methods])
    allow(engine).to receive(:select_subjects).with([target.file], test_files: []).and_return([[target], nil])
    allow(engine).to receive(:check_baseline).with(integration, 3)
    map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
    store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false, fetch: map)
    expect(Saboteur::Engine::CoverageStore).to receive(:new) do |load_methods:, **|
      expect(load_methods).to eq(target.file => [2])
      store
    end
    allow(engine).to receive(:candidate_lists).and_return([[]])
    expect(engine.call.results).to eq([])
  end
  it "uses method calls to exclude uncalled shared def/body lines" do
    file = source_file("def called = 1\ndef uncalled = 2\ndef multi\n  3\nend\n")
    boot_calls(file => Set[[1, :called]])
    allow(fake_coverage).to receive(:result).and_return(file => { lines: [1, 1, 1, 1] })
    expect(Saboteur::Engine::LoadCoverage.capture([file]).first).to eq(file => [1, 3, 4])
  end

  it "discards an ambiguous shared line when a sibling method was never called" do
    file = source_file("def used = 1; def unused = 2\n")
    expect(Saboteur::Engine::LoadCoverage.uncalled_shared_lines(file, Set[[1, :used]])).to eq([1])
  end

  it "retains a shared line only when every method defined there was called" do
    file = source_file("def first = 1; def second = 2\n")
    expect(Saboteur::Engine::LoadCoverage.uncalled_shared_lines(file, Set[[1, :first], [1, :second]])).to eq([])
  end

  it "treats one-line define_method blocks like one-line defs" do
    file = source_file("define_method(:a) { 1 }\ndef b; 2; end\n" \
                       "define_method(:c) { 3 }; define_singleton_method(:d) { 4 }\n")
    expect(Saboteur::Engine::LoadCoverage.uncalled_shared_lines(file, Set.new)).to eq([1, 2, 3])
    expect(Saboteur::Engine::LoadCoverage.uncalled_shared_lines(file, Set[[3, :c]])).to eq([1, 2, 3])
    expect(Saboteur::Engine::LoadCoverage.uncalled_shared_lines(file,
                                                                Set[[1, :a], [2, :b], [3, :c], [3, :d]])).to eq([])
  end

  it "ignores calls that are not a define_method with a block and a literal symbol name" do
    file = source_file("memoize(:z) { 1 }\ndefine_method { 1 }\ndefine_method(\"s\") { 1 }\n" \
                       "define_method(:a, impl)\ndefine_method(name) { 1 }\ndefine_method(:b) do\n  1\nend\n")
    expect(Saboteur::Engine::LoadCoverage.uncalled_shared_lines(file, Set.new)).to eq([])
  end

  it "names a one-line define_method by its first argument" do
    file = source_file("define_method(:e, :f) { 1 }\n")
    expect(Saboteur::Engine::LoadCoverage.uncalled_shared_lines(file, Set[[1, :e]])).to eq([])
  end

  it "reports no shared lines for an unreadable file" do
    expect(Saboteur::Engine::LoadCoverage.uncalled_shared_lines(File.join(root, "gone.rb"), Set.new)).to eq([])
  end

  it "pauses the booted call tracer as soon as coverage is suspended, and copes without one" do
    guard = instance_double(Saboteur::Engine::CoverageGuard, suspend: nil)
    allow(Saboteur::Engine::CoverageGuard).to receive(:new).and_return(guard)
    allow(Saboteur::Engine::LoadCoverage).to receive(:capture).and_return([{}, {}])
    tracer = instance_double(Saboteur::MethodCalls, pause: nil)
    allow(Saboteur::MethodCalls).to receive(:booted).and_return(tracer)
    engine.send(:suspend_coverage, [])
    expect(tracer).to have_received(:pause)
    allow(Saboteur::MethodCalls).to receive(:booted).and_return(nil)
    expect { engine.send(:suspend_coverage, []) }.not_to raise_error
  end

  it "disables the boot tracer when it reads the boot calls" do
    file = File.realpath(__FILE__)
    tracer = instance_double(Saboteur::MethodCalls, disable: nil, drain: { file => Set[[3, :called]] })
    allow(Saboteur::MethodCalls).to receive(:booted).and_return(tracer)
    allow(fake_coverage).to receive(:result).and_return(file => { lines: [] })
    Saboteur::Engine::LoadCoverage.capture([file])
    expect(tracer).to have_received(:disable)
  end

  it "merges the calls of two spellings of one file instead of keeping the last" do
    file = source_file("def one = 1\ndef two = 2\n")
    respelled = File.join(File.dirname(file), ".", File.basename(file))
    boot_calls(file => Set[[1, :one]], respelled => Set[[2, :two]])
    allow(fake_coverage).to receive(:result).and_return(file => { lines: [] })
    expect(Saboteur::Engine::LoadCoverage.capture([file]).last).to eq(file => [1, 2])
  end
end
