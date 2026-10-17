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
  it "keeps only positive method-call counters for included files" do
    file = File.realpath(__FILE__)
    methods = { [Object, :called, 3, 0, 5, 20] => 2, [Object, :skipped, 8, 0, 9, 20] => 0 }
    allow(fake_coverage).to receive(:result).and_return(
      file => { lines: [],
                methods: methods }, "/outside.rb" => { lines: [], methods: { [Object, :x, 1, 0, 1, 2] => 1 } }
    )
    expect(Saboteur::Engine::LoadCoverage.capture([file])).to eq([{}, { file => [3] }])
    expect(Saboteur::Engine::LoadCoverage.capture([])).to eq([{}, {}])
    allow(fake_coverage).to receive(:state).and_return(:running)
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
                                                              load_methods:, supervisor:, diagnostics:, timeout_cap:|
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
  it "uses method-call counters to exclude uncalled shared def/body lines" do
    file = File.realpath(__FILE__)
    methods = { [Object, :called, 1, 0, 1, 20] => 2, [Object, :uncalled, 2, 0, 2, 20] => 0,
                [Object, :multi, 3, 0, 5, 3] => 0 }
    allow(fake_coverage).to receive(:result).and_return(file => { lines: [1, 1, 1, 1], methods: methods })
    expect(Saboteur::Engine::LoadCoverage.capture([file]).first).to eq(file => [1, 3, 4])
  end

  it "discards an ambiguous shared line when a sibling method was never called" do
    data = { methods: { [Object, :unused, 1, 0, 1, 10] => 0, [Object, :used, 1, 12, 1, 20] => 1 } }
    expect(Saboteur::Engine::LoadCoverage.uncalled_shared_lines(data)).to eq([1])
  end
  it "retains a shared line only when every method defined there was called" do
    data = { methods: { [Object, :first, 1, 0, 1, 10] => 1, [Object, :second, 1, 12, 1, 20] => 2 } }
    expect(Saboteur::Engine::LoadCoverage.uncalled_shared_lines(data)).to eq([])
  end
end
