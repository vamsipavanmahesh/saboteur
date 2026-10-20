# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "fileutils"
require "tmpdir"

RSpec.describe Saboteur::Engine::CoverageStore, "shadow run (#46)" do
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
  let(:rerun_map_wrong) do
    Saboteur::Selection::CoverageMap.new(lines: { file => { 2 => [x_id] } }, tests: [x_id], durations: { x_id => 1.0 })
  end
  let(:err) { StringIO.new }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(err) }

  let(:parts) { 1 }

  def store(timeout_cap: nil, **settings)
    config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)
    described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                        supervisor: supervisor, diagnostics: diagnostics, parts: parts,
                        timeout_cap: timeout_cap).tap do |built|
      allow(built).to receive(:build).and_return(map)
    end
  end

  def child_result(rerun_map)
    Saboteur::Execution::Supervisor::Result.new(payload: rerun_map.to_json, exit_status: nil, stopped_by: nil,
                                                detail: nil, runtime: 0.1, leftover_pids: [])
  end

  def reports
    Dir[File.join(@root, ".saboteur", "shadow-*.json")].map { |path| JSON.parse(File.read(path)) }
  end

  def first_run(**settings)
    store(partial_coverage: "shadow", seed: 5, **settings).fetch([file])
    File.write(x_file, "2\n")
  end

  it "does nothing by default: no rerun, no report" do
    store.fetch([file])
    File.write(x_file, "2\n")
    expect(supervisor).not_to receive(:run)
    store.fetch([file])
    expect(reports).to eq([])
    expect(diagnostics.warnings).to eq([])
  end

  it "writes no report on the first miss, where there is no earlier map" do
    store(partial_coverage: "shadow").fetch([file])
    expect(reports).to eq([])
  end

  it "hands the child the earlier map's seed and exactly the stale spec files" do
    first_run
    built = store(partial_coverage: "shadow", seed: 9)
    writer = StringIO.new
    allow(supervisor).to receive(:run) { |**, &block| block.call(writer) && child_result(rerun_map) }
    allow(built).to receive(:record).and_return(true)
    built.fetch([file])

    expect(built).to have_received(:record).with(writer, [file], only: [x_file], seed: 5)
  end

  it "reruns only the changed spec file with the earlier map's seed, and reports a match" do
    first_run
    expect(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap).at_least(:once)
    expect(supervisor).to receive(:run).once
                                       .with(timeout: 123, label: /shadow rerun/)
                                       .and_return(child_result(rerun_map))
    expect(integration).to receive(:run_all).never
    store(partial_coverage: "shadow", seed: 9, coverage_timeout: 123).fetch([file])

    expect(reports.size).to eq(1)
    expect(reports.first).to include("result" => "match", "stale" => ["spec/x_spec.rb"], "threshold" => 0.5)
    expect(diagnostics.warnings).to eq([])
  end

  it "warns and still uses the full map when the partial map differs" do
    first_run
    other = File.join(@root, "b.rb")
    wrong = Saboteur::Selection::CoverageMap.new(lines: { file => { 2 => [x_id] }, other => { 1 => [x_id] } },
                                                 tests: [x_id],
                                                 durations: { x_id => 1.0 })
    allow(supervisor).to receive(:run).and_return(child_result(wrong))
    result = store(partial_coverage: "shadow").fetch([file])

    expect(result.lines[file]).to eq(1 => [x_id, y_id])
    expect(reports.first["result"]).to eq("mismatch")
    message = diagnostics.warnings.join
    expect(message).to match(Regexp.new(["\\Apartial coverage shadow run: this run used the full map\\n  ",
                                         "the partial map differs from the full map in 2 place\\(s\\), first lines ",
                                         Regexp.escape(file), "\\n  ",
                                         "Report: \\S+shadow-\\w+\\.json\\z"].join))
  end

  it "skips with a reason, and runs nothing, when a fixture changed" do
    FileUtils.mkdir_p(File.join(@root, "spec", "fixtures"))
    File.write(File.join(@root, "spec", "fixtures", "d.yml"), "a: 1\n")
    first_run
    File.write(File.join(@root, "spec", "fixtures", "d.yml"), "a: 2\n")
    expect(supervisor).not_to receive(:run)
    store(partial_coverage: "shadow").fetch([file])

    expect(reports.first).to include("result" => "skipped")
  end

  it "records the seconds the full build and the partial rerun took" do
    first_run
    ticks = [10.0, 12.346, 20.0, 20.254].each
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { ticks.next }
    allow(supervisor).to receive(:run).and_return(child_result(rerun_map))
    store(partial_coverage: "shadow").fetch([file])

    expect(reports.first).to include("full_build_seconds" => 2.35, "rerun_seconds" => 0.25)
  end

  it "records the build seconds and no rerun seconds when the shadow step skips" do
    first_run
    File.write(file, "2\n")
    File.write(File.join(@root, "other.yml"), "x\n")
    ticks = [1.0, 4.126].each
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { ticks.next }
    store(partial_coverage: "shadow").fetch([file])

    expect(reports.first).to include("full_build_seconds" => 3.13, "rerun_seconds" => nil)
  end

  it "reuses the map for ordinary RSpec arguments and option files" do
    File.write(File.join(@root, ".rspec"), "--format progress\n")
    first_run(rspec_args: ["--order", "defined"])
    allow(supervisor).to receive(:run).and_return(child_result(rerun_map))
    store(partial_coverage: "shadow", rspec_args: ["--order", "defined"]).fetch([file])

    expect(reports.first).to include("result" => "match")
  end

  it "skips, and runs nothing, when the framework selects examples from its status file" do
    first_run
    allow(integration).to receive(:status_file?).with(@root).and_return(true)
    expect(supervisor).not_to receive(:run)
    store(partial_coverage: "shadow").fetch([file])

    expect(reports.first).to include("result" => "skipped")
  end

  it "writes the report privately, through a fresh temporary name" do
    first_run
    allow(supervisor).to receive(:run).and_return(child_result(rerun_map))
    store(partial_coverage: "shadow").fetch([file])

    path = Dir[File.join(@root, ".saboteur", "shadow-*.json")].first
    expect(File.stat(path).mode & 0o777).to eq(0o600)
    expect(Dir[File.join(@root, ".saboteur", "shadow-*.tmp")]).to eq([])
  end

  it "never stops the run when the rerun fails, and says so" do
    first_run
    allow(supervisor).to receive(:run).and_raise(Saboteur::Error, "child gone")
    result = store(partial_coverage: "shadow").fetch([file])

    expect(result.tests).to eq([x_id, y_id])
    expect(diagnostics.warnings.join).to include("partial coverage shadow run failed, so the full map is used\n  " \
                                                 "child gone")
  end

  it "stays off for a scoped build" do
    first_run
    expect(supervisor).not_to receive(:run)
    store(partial_coverage: "shadow", tests: ["spec/x_spec.rb"]).fetch([file])
    expect(reports).to eq([])
  end

  context "when only one spec file reads the source file" do
    let(:map) do
      Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => [y_id] } }, tests: [x_id, y_id],
                                           durations: { x_id => 1.0, y_id => 1.0 })
    end
    let(:rerun_map) do
      Saboteur::Selection::CoverageMap.new(lines: { file => { 1 => [y_id] } }, tests: [y_id],
                                           durations: { y_id => 1.0 })
    end

    it "reruns just that spec file when the source file changed" do
      store(partial_coverage: "shadow").fetch([file])
      File.write(file, "2\n")
      allow(supervisor).to receive(:run).and_return(child_result(rerun_map))
      store(partial_coverage: "shadow").fetch([file])

      expect(reports.first).to include("result" => "match", "stale" => ["spec/y_spec.rb"])
    end
  end

  it "says when the --max-duration budget stops the rerun" do
    first_run
    stopped = Saboteur::Execution::Supervisor::Result.new(payload: "", exit_status: nil, stopped_by: :timeout,
                                                          detail: nil, runtime: 0.1, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(stopped)
    store(partial_coverage: "shadow", coverage_timeout: 100, timeout_cap: ->(_) { 50 }).fetch([file])

    expect(diagnostics.warnings.join).to include("the --max-duration budget stopped the coverage map build")
  end

  it "stays off without the cache" do
    first_run
    expect(supervisor).not_to receive(:run)
    store(partial_coverage: "shadow", cache: false).fetch([file])
    expect(reports).to eq([])
  end

  context "with a parted build" do
    let(:parts) { 2 }

    it "stays off" do
      first_run
      expect(supervisor).not_to receive(:run)
      store(partial_coverage: "shadow").fetch([file])
      expect(reports).to eq([])
    end
  end

  describe "cleaning what it prints and writes" do
    let(:hostile) { "evil\n::warning::x\e[31m##[error]y" }
    let(:clean) { "evil\\x0a::warning::x##\\x5berror]y" }

    it "cleans a hostile stale spec file name in the report" do
      hostile_file = File.join(@root, "spec", "#{hostile}_spec.rb")
      File.write(hostile_file, "1\n")
      allow(integration).to receive(:test_files).and_return([x_file, hostile_file])
      first_run
      File.write(hostile_file, "2\n")
      allow(supervisor).to receive(:run).and_return(child_result(rerun_map))
      store(partial_coverage: "shadow").fetch([file])

      expect(reports.first["stale"]).to include("spec/#{clean}_spec.rb")
    end

    it "cleans a hostile difference name in the report" do
      hostile_file = File.join(@root, "#{hostile}.rb").tap { |path| File.write(path, "1\n") }
      wrong = Saboteur::Selection::CoverageMap.new(lines: { hostile_file => { 1 => [x_id] } }, tests: [x_id],
                                                   durations: { x_id => 1.0 })
      first_run
      allow(supervisor).to receive(:run).and_return(child_result(wrong))
      store(partial_coverage: "shadow").fetch([file])

      names = reports.first["differences"].map { |item| item["name"] }
      expect(names).to include("#{@root}/#{clean}.rb")
      expect(names.join).not_to match(/[\n\e]/)
    end

    it "cleans a hostile cache path in the mismatch warning" do
      dir = "cache\n::warning::z"
      first = store(partial_coverage: "shadow", cache_dir: dir)
      first.fetch([file])
      File.write(x_file, "2\n")
      allow(supervisor).to receive(:run).and_return(child_result(rerun_map_wrong))
      store(partial_coverage: "shadow", cache_dir: dir).fetch([file])

      expect(diagnostics.warnings.join).to include("Report: #{@root}/cache\\x0a::warning::z/shadow-")
    end

    it "cleans a hostile exception message in the failure warning" do
      first_run
      allow(supervisor).to receive(:run).and_raise(Saboteur::Error, hostile)
      store(partial_coverage: "shadow").fetch([file])

      expect(diagnostics.warnings.last).to end_with("so the full map is used\n  #{clean}")
    end
  end

  it "removes its temporary report when it cannot move it into place" do
    first_run
    allow(supervisor).to receive(:run).and_return(child_result(rerun_map))
    allow(File).to receive(:rename).and_call_original
    allow(File).to receive(:rename).with(%r{/shadow-\w+\.json\.\h+\.tmp\z}, anything).and_raise(Errno::EACCES)
    begin
      store(partial_coverage: "shadow").fetch([file])
    rescue StandardError
      nil
    end
    expect(Dir[File.join(@root, ".saboteur", "shadow-*.tmp")]).to eq([])
  end
end
