# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# Per-worker database copies exist only for one run: the engine drops them
# after distribution, whether the run passed, failed or raised.
RSpec.describe Saboteur::Engine, "worker database cleanup" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:subject_under_test) do
    subjects_in("class CleanupTarget\n  def m\n    1\n  end\nend\n", name: "cleanup_target.rb").first
  end
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => ["t1"] } }, tests: ["t1"])
  end
  let(:integration) { instance_double(Saboteur::Integration::RSpec, test_files: []) }
  let(:rails) { instance_double(Saboteur::Frameworks::Rails, prepare_workers: nil, cleanup_workers: nil) }
  let(:err) { StringIO.new }

  def run_engine(events, run_error: nil, prepare_error: nil, cleanup_error: nil)
    stub_boot_phase
    stub_test_phase(events, run_error, prepare_error, cleanup_error)
    described_class.new(Saboteur::Config.new({ "jobs" => 2 }, root: @root), err: err).call
  end

  def stub_boot_phase
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: rails)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject_under_test], changed_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
  end

  def stub_test_phase(events, run_error, prepare_error, cleanup_error)
    stub_baseline_and_store
    stub_distribution(events, run_error)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
    if prepare_error
      allow(rails).to receive(:prepare_workers) { events << :prepare and raise(prepare_error) }
    else
      allow(rails).to receive(:prepare_workers) { events << :prepare }
    end
    if cleanup_error
      allow(rails).to receive(:cleanup_workers) { events << :cleanup and raise(cleanup_error) }
    else
      allow(rails).to receive(:cleanup_workers) { events << :cleanup }
    end
  end

  def stub_baseline_and_store
    baseline = instance_double(Saboteur::Engine::BaselineGuard, call: nil)
    allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(baseline)
    store = instance_double(Saboteur::Engine::CoverageStore)
    allow(store).to receive(:fetch).and_return(map)
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
  end

  def stub_distribution(events, run_error)
    distribution = instance_double(Saboteur::Engine::Distribution)
    allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
    if run_error
      allow(distribution).to receive(:run) { events << :distribute and raise(run_error) }
    else
      allow(distribution).to receive(:run) { events << :distribute and [] }
    end
  end

  it "drops the worker databases after a successful run" do
    events = []
    run_engine(events)
    expect(events).to eq(%i[prepare distribute cleanup])
  end

  it "drops the worker databases even when the run raises" do
    events = []
    expect { run_engine(events, run_error: "boom") }.to raise_error("boom")
    expect(events).to eq(%i[prepare distribute cleanup])
  end

  it "drops the copies a failed prepare actually made" do
    events = []
    expect { run_engine(events, prepare_error: "disk full") }.to raise_error("disk full")
    expect(events).to eq(%i[prepare cleanup])
  end

  it "warns about a cleanup failure instead of masking the run's outcome" do
    report = run_engine([], cleanup_error: Saboteur::Error.new("could not drop worker database copies: x"))
    expect(report.warnings).to include("could not drop worker database copies: x")
  end
end
