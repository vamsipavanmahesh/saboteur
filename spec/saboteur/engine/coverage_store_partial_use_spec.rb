# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "fileutils"
require "tmpdir"

RSpec.describe Saboteur::Engine::CoverageStore, "partial coverage use (#46)" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  before do
    allow(Saboteur::CoverageReads).to receive(:result).and_return({})
    allow(Coverage).to receive(:state).and_return(:suspended)
    FileUtils.mkdir_p(File.join(@root, "spec"))
    File.write(File.join(@root, "spec", "x_spec.rb"), "1\n")
    File.write(File.join(@root, "spec", "y_spec.rb"), "1\n")
  end

  let(:file) { File.join(@root, "a.rb").tap { |path| File.write(path, "1\n") } }
  let(:x_file) { File.join(@root, "spec", "x_spec.rb") }
  let(:x_id) { "./spec/x_spec.rb[1:1]" }
  let(:y_id) { "./spec/y_spec.rb[1:1]" }
  let(:integration) do
    instance_double(Saboteur::Integration::RSpec, test_files: [x_file, File.join(@root, "spec", "y_spec.rb")],
                                                  status_file?: false)
  end
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => [x_id, y_id] } }, tests: [x_id, y_id],
                                         durations: { x_id => 1.0, y_id => 1.0 })
  end
  let(:rerun_map) do
    Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => [x_id] } }, tests: [x_id], durations: { x_id => 1.0 })
  end
  let(:err) { StringIO.new }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(err) }

  def store(parts: 1, **settings)
    config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: diagnostics, parts: parts).tap do |built|
      allow(built).to receive(:build).and_return(map)
    end
  end

  def child_result(rerun)
    Saboteur::Execution::Supervisor::Result.new(payload: rerun.to_json, exit_status: nil, stopped_by: nil,
                                                detail: nil, runtime: 0.1, leftover_pids: [])
  end

  def first_run(mode: "use")
    store(partial_coverage: mode, seed: 5).fetch([file])
    File.write(x_file, "2\n")
  end

  def ids(result)
    result.lines.fetch(file).fetch(1).sort
  end

  it "builds the full map when there is no earlier map to start from" do
    built = store(partial_coverage: "use")
    expect(built.fetch([file]).tests).to eq(map.tests)
    expect(built).to have_received(:build).once
  end

  it "reruns only the stale spec file with the earlier seed and never builds the whole suite" do
    first_run
    built = store(partial_coverage: "use", seed: 9)
    writer = StringIO.new
    allow(supervisor).to receive(:run) { |**, &block| block.call(writer) && child_result(rerun_map) }
    allow(built).to receive(:record).and_return(true)
    result = built.fetch([file])

    expect(built).to have_received(:record).with(writer, [file], only: [x_file], seed: 5)
    expect(built).not_to have_received(:build)
    expect(ids(result)).to eq([x_id, y_id].sort)
    expect(result.tests.sort).to eq([x_id, y_id].sort)
  end

  it "uses the earlier map as it is when no spec file is stale" do
    first_run
    allow(Saboteur::Engine::PartialInvalidation)
      .to receive(:new).and_return(instance_double(Saboteur::Engine::PartialInvalidation, stale_specs: []))
    built = store(partial_coverage: "use", seed: 9)
    expect(supervisor).not_to receive(:run)
    expect(built.fetch([file]).tests.sort).to eq([x_id, y_id].sort)
    expect(built).not_to have_received(:build)
  end

  it "says it reused the earlier map and how many spec files it reran" do
    first_run
    allow(supervisor).to receive(:run).and_return(child_result(rerun_map))
    store(partial_coverage: "use").fetch([file])
    expect(err.string).to include("reusing the earlier coverage map, rerunning 1 of 2 spec files")
  end

  it "saves the merged map so the next run is a plain cache hit" do
    first_run
    allow(supervisor).to receive(:run).and_return(child_result(rerun_map))
    store(partial_coverage: "use").fetch([file])
    again = store(partial_coverage: "use")
    expect(again.reusable?([file])).to be(true)
  end

  it "builds the full map when the change needs a full rebuild" do
    FileUtils.mkdir_p(File.join(@root, "spec", "fixtures"))
    File.write(File.join(@root, "spec", "fixtures", "d.yml"), "a: 1\n")
    first_run
    File.write(File.join(@root, "spec", "fixtures", "d.yml"), "a: 2\n")
    built = store(partial_coverage: "use")
    expect(supervisor).not_to receive(:run)
    expect(built.fetch([file]).tests).to eq(map.tests)
    expect(built).to have_received(:build).once
  end

  it "builds the full map, and says why, when the partial rerun fails" do
    first_run
    allow(supervisor).to receive(:run).and_raise(Saboteur::Error, "child died")
    built = store(partial_coverage: "use")
    expect(built.fetch([file]).tests).to eq(map.tests)
    expect(diagnostics.warnings.join).to include("partial coverage failed, so the full map is built", "child died")
  end

  it "does not try the partial path unless the mode is use, the cache is on, the run is whole-suite and one part" do
    first_run
    [{ partial_coverage: "off" }, { partial_coverage: "shadow" }, { partial_coverage: "use", cache: false },
     { partial_coverage: "use", tests: [x_file] },
     { partial_coverage: "use", parts: 2 }].each_with_index do |settings, index|
      File.write(x_file, "#{index + 10}\n")
      built = store(**settings)
      allow(built).to receive(:partial_map).and_call_original
      allow(supervisor).to receive(:run).and_return(child_result(rerun_map))
      built.fetch([file])
      expect(built).not_to have_received(:partial_map), settings.inspect
      expect(built).to have_received(:build).at_least(:once), settings.inspect
    end
  end

  it "tries the partial path in use mode" do
    first_run
    built = store(partial_coverage: "use")
    allow(built).to receive(:partial_map).and_call_original
    allow(supervisor).to receive(:run).and_return(child_result(rerun_map))
    built.fetch([file])
    expect(built).to have_received(:partial_map).once
  end

  it "builds the full map without a warning when the earlier map file is gone" do
    first_run
    Dir[File.join(@root, ".saboteur", "coverage-*.json")].each { |path| File.delete(path) }
    built = store(partial_coverage: "use")
    expect(built.fetch([file]).tests).to eq(map.tests)
    expect(diagnostics.warnings).to eq([])
  end

  it "keeps the preloaded files in the merged map" do
    first_run
    allow(Saboteur::Engine::LoadCoverage).to receive(:preloaded_uninstrumented)
      .and_return([Saboteur::Selection::CoverageMap.canonical(file)])
    allow(supervisor).to receive(:run).and_return(child_result(rerun_map))
    expect(store(partial_coverage: "use").fetch([file]).preloaded?(file)).to be(true)
  end

  it "builds the full map without a warning when the merged map has no tests" do
    first_run
    empty = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [])
    allow(supervisor).to receive(:run).and_return(child_result(empty))
    allow(Saboteur::Engine::PartialMerge).to receive(:call).and_return(empty)
    expect(store(partial_coverage: "use").fetch([file]).tests).to eq(map.tests)
    expect(diagnostics.warnings).to eq([])
  end

  it "builds the full map when the merged map has line evidence but lists no tests" do
    first_run
    no_tests = Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => [x_id] } }, tests: [])
    allow(supervisor).to receive(:run).and_return(child_result(rerun_map))
    allow(Saboteur::Engine::PartialMerge).to receive(:call).and_return(no_tests)
    expect(store(partial_coverage: "use").fetch([file]).tests).to eq(map.tests)
  end

  it "builds the full map, with a warning, when the merged map has no evidence for the included files" do
    first_run
    other = Saboteur::Selection::CoverageMap.new(lines: { File.join(@root, "b.rb") => { 1 => [x_id] } },
                                                 tests: [x_id], durations: { x_id => 1.0 })
    allow(supervisor).to receive(:run).and_return(child_result(other))
    allow(Saboteur::Engine::PartialMerge).to receive(:call).and_return(other)
    expect(store(partial_coverage: "use").fetch([file]).tests).to eq(map.tests)
    expect(diagnostics.warnings.join).to include("partial coverage failed, so the full map is built")
  end

  it "lets a spent budget stop the run instead of falling back to a full build" do
    first_run
    allow(supervisor).to receive(:run).and_raise(Saboteur::BudgetPhaseTimeout, "out of time")
    built = store(partial_coverage: "use")
    expect { built.fetch([file]) }.to raise_error(Saboteur::BudgetPhaseTimeout)
    expect(built).not_to have_received(:build)
  end
end
