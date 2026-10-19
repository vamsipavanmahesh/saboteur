# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "fileutils"
require "tmpdir"

# The coverage build split into parallel parts (#741).
RSpec.describe Saboteur::Engine::CoverageStore, "in parts" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  before do
    allow(Saboteur::CoverageReads).to receive(:result).and_return({})
    allow(Coverage).to receive(:state).and_return(:suspended)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
  end

  let(:source) { File.join(@root, "a.rb").tap { |path| File.write(path, "1\n") } }
  let(:spec_files) { %w[/s/a_spec.rb /s/b_spec.rb /s/c_spec.rb] }
  let(:integration) { instance_double(Saboteur::Integration::RSpec, test_files: spec_files) }
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }

  let(:output) { StringIO.new }

  def store(parts: 2, timeout_cap: nil)
    config = Saboteur::Config.new({}, root: @root)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(output),
                        parts: parts, timeout_cap: timeout_cap)
  end

  def part_map(*tests)
    lines = tests.to_h { |test| [1, [test]] }
    Saboteur::Selection::CoverageMap.new(lines: { source => lines }, tests: tests)
  end

  def result(map, stopped_by: nil)
    Saboteur::Execution::Supervisor::Result.new(payload: map&.to_json, exit_status: nil,
                                                stopped_by: stopped_by, detail: "stopped", runtime: 0.1,
                                                leftover_pids: [])
  end

  # Parts of [a, c] and [b]: 3 examples in all.
  def counts(total: 3, first: 2, second: 1)
    allow(integration).to receive(:example_count).with(no_args).and_return(total)
    allow(integration).to receive(:example_count).with(files: %w[/s/a_spec.rb /s/c_spec.rb]).and_return(first)
    allow(integration).to receive(:example_count).with(files: %w[/s/b_spec.rb]).and_return(second)
  end

  it "combines the parts' maps, in part order, into one map" do
    counts
    expect(supervisor).to receive(:run_many)
      .with(2, hash_including(label: "coverage child died during the map build"))
      .and_return([result(part_map("t1", "t3")), result(part_map("t2"))])

    map = store.fetch([source])

    expect(map.tests).to eq(%w[t1 t3 t2])
  end

  it "gives each part its own spec files and its own log" do
    counts
    parted = store
    allow(parted).to receive(:record)
    allow(supervisor).to receive(:run_many) do |_count, **_options, &block|
      block.call(:writer, 1)
      [result(part_map("t1", "t3")), result(part_map("t2"))]
    end

    parted.fetch([source])

    expect(parted).to have_received(:record)
      .with(:writer, [source], only: %w[/s/b_spec.rb], log: File.join(@root, ".saboteur", "coverage-build-2.log"))
  end

  it "announces the parts, prepares the heap once and ticks the progress heartbeat" do
    counts
    expect(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap).once
    expect(supervisor).to receive(:run_many)
      .with(2, hash_including(on_tick: an_instance_of(Method), timeout: 3600.0))
      .and_return([result(part_map("t1", "t3")), result(part_map("t2"))])

    store.fetch([source])

    expect(output.string).to include("building coverage map (runs the suite once, in 2 parallel parts)")
  end

  it "labels the parts heartbeat as the coverage map build" do
    counts
    diagnostics = Saboteur::Engine::Diagnostics.new(output)
    allow(supervisor).to receive(:run_many).and_return([result(part_map("t1", "t3")), result(part_map("t2"))])
    expect(diagnostics).to receive(:progress_heartbeat).with("building coverage map").and_call_original
    config = Saboteur::Config.new({}, root: @root)

    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: diagnostics, parts: 2).fetch([source])
  end

  it "raises BudgetPhaseTimeout with the admitted time when a part is cut short by the budget" do
    counts
    allow(supervisor).to receive(:run_many)
      .and_return([result(part_map("t1", "t3")), result(nil, stopped_by: :timeout)])

    expect { store(timeout_cap: ->(timeout) { timeout / 2 }).fetch([source]) }
      .to raise_error(Saboteur::BudgetPhaseTimeout, /admitted 1800.0s of the 3600.0s phase timeout/)
  end

  it "keeps a part that recorded tests but no line hits" do
    counts
    dark = Saboteur::Selection::CoverageMap.new(lines: {}, tests: %w[t1 t3])
    allow(supervisor).to receive(:run_many).and_return([result(dark), result(part_map("t2"))])

    expect(store.fetch([source]).tests).to eq(%w[t1 t3 t2])
  end

  it "refuses to build when the parts do not hold the suite's examples, before running anything" do
    counts(total: 4)
    expect(supervisor).not_to receive(:run_many)

    expect { store.fetch([source]) }.to raise_error(
      Saboteur::Error,
      "the coverage parts hold 3 examples but the suite has 4; " \
      "refusing to build a map from a partition that does not cover the suite"
    )
  end

  it "refuses a part that recorded no tests" do
    counts
    allow(supervisor).to receive(:run_many).and_return([result(part_map("t1", "t3")), result(part_map)])

    expect { store.fetch([source]) }.to raise_error(
      Saboteur::Error, "coverage part 2 of 2 recorded no tests; refusing to build a partial map"
    )
  end

  it "refuses a combined map that holds fewer tests than the suite has examples" do
    counts
    allow(supervisor).to receive(:run_many).and_return([result(part_map("t1")), result(part_map("t2"))])

    expect { store.fetch([source]) }.to raise_error(
      Saboteur::Error, "the combined coverage map holds 2 tests but the suite has 3; refusing to use a partial map"
    )
  end

  it "fails when one part was stopped, instead of using the others" do
    counts
    allow(supervisor).to receive(:run_many)
      .and_return([result(part_map("t1", "t3")), result(nil, stopped_by: :timeout)])

    expect { store.fetch([source]) }.to raise_error(Saboteur::Error, /coverage map build stopped/)
  end

  it "keeps the single child build when the suite has fewer files than parts" do
    allow(integration).to receive(:test_files).and_return(%w[/s/a_spec.rb])
    expect(supervisor).to receive(:run).and_return(result(part_map("t1")))
    expect(supervisor).not_to receive(:run_many)

    expect(store.fetch([source]).tests).to eq(%w[t1])
  end

  it "keeps the single child build by default and never counts examples or deals parts" do
    expect(integration).not_to receive(:example_count)
    expect(Saboteur::Engine::SuitePartition).not_to receive(:parts)
    expect(supervisor).to receive(:run).and_return(result(part_map("t1")))

    expect(store(parts: 1).fetch([source]).tests).to eq(%w[t1])
  end

  it "treats a parts value below 2 as the single child build" do
    expect(Saboteur::Engine::SuitePartition).not_to receive(:parts)
    expect(supervisor).to receive(:run).and_return(result(part_map("t1")))

    expect(store(parts: 0).fetch([source]).tests).to eq(%w[t1])
  end

  describe "recording one part" do
    it "runs the whole suite, with no files argument, when no part is given" do
      recorder = instance_double(Saboteur::Selection::Recorder, start: nil)
      allow(recorder).to receive(:result).and_return(part_map("t1"))
      allow(Saboteur::Selection::Recorder).to receive(:new).and_return(recorder)
      expect(integration).to receive(:run_all).with(recorder).and_return(true)
      whole = store
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(whole).to receive(:exit!)

      whole.send(:record, StringIO.new, [source])
    end

    it "runs only that part's files and writes to the part's log" do
      recorder = instance_double(Saboteur::Selection::Recorder, start: nil)
      allow(recorder).to receive(:result).and_return(part_map("t1"))
      allow(Saboteur::Selection::Recorder).to receive(:new).and_return(recorder)
      expect(integration).to receive(:run_all).with(recorder, files: %w[/s/b_spec.rb]).and_return(true)
      part_store = store
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
      allow(part_store).to receive(:exit!)
      log = File.join(@root, "logs", "part.log")

      part_store.send(:record, StringIO.new, [source], only: %w[/s/b_spec.rb], log: log)

      expect($stdout).to have_received(:reopen).with(log, "w")
      expect(File.directory?(File.dirname(log))).to be(true)
    end
  end
end
