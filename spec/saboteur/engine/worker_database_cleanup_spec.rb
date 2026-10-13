# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# Per-worker database copies exist only for one run: the engine drops them
# after distribution, whether the run passed, failed or raised.
RSpec.describe Saboteur::Engine, "worker database cleanup" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return({})
  end

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

  def run_engine(events, run_error: nil, prepare_error: nil, cleanup_error: nil, rails: self.rails,
                 subjects: [subject_under_test], boot_error: nil, baseline_error: nil)
    stub_boot_phase(rails, subjects, boot_error)
    stub_test_phase(events, run_error, prepare_error, cleanup_error, baseline_error)
    described_class.new(Saboteur::Config.new({ "jobs" => 2 }, root: @root), err: err).call
  end

  def stub_boot_phase(rails, subjects, boot_error)
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    boot = instance_double(Saboteur::Engine::Boot, rails: rails)
    if boot_error
      # A boot that raises partway through has already built the Rails
      # profile (Boot assigns it before after_boot), so it stays reachable
      # for cleanup.
      allow(boot).to receive(:load_target).and_raise(boot_error)
    else
      allow(boot).to receive(:load_target).and_return(integration)
    end
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    selection = instance_double(Saboteur::Engine::SubjectSelection, select: subjects, changed_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
  end

  def stub_test_phase(events, run_error, prepare_error, cleanup_error, baseline_error)
    stub_baseline_and_store(baseline_error)
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

  def stub_baseline_and_store(baseline_error)
    baseline = instance_double(Saboteur::Engine::BaselineGuard)
    if baseline_error
      allow(baseline).to receive(:call).and_raise(baseline_error)
    else
      allow(baseline).to receive(:call)
    end
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

  # No subjects: mutate never runs, so only the Engine.call boundary can
  # release what the boot snapshotted.
  it "drops the worker databases when nothing needs mutating" do
    events = []
    run_engine(events, subjects: [])
    expect(events).to eq(%i[cleanup])
  end

  # The baseline fails before prepare_workers: only the Engine.call
  # boundary can release what the boot snapshotted.
  it "drops the worker databases when the baseline run fails" do
    events = []
    expect { run_engine(events, baseline_error: "baseline failed") }.to raise_error("baseline failed")
    expect(events).to eq(%i[cleanup])
  end

  # A boot that raised partway through: load_target never returned, but
  # the snapshots it took still go.
  it "drops the worker databases a boot that raised partway through already made" do
    events = []
    expect { run_engine(events, boot_error: "boot exploded") }.to raise_error("boot exploded")
    expect(events).to eq(%i[cleanup])
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

  # A non-Rails project has no copies to drop; cleanup must be skipped
  # silently, not warn about a nil cleanup call.
  it "does nothing and warns about nothing when the project has no Rails databases" do
    events = []
    report = run_engine(events, rails: nil)
    expect(events).to eq(%i[distribute])
    expect(report.warnings.grep(/undefined method|cleanup/)).to be_empty
  end

  it "warns about an unanticipated cleanup error instead of masking the run's outcome" do
    report = run_engine([], cleanup_error: StandardError.new("handler exploded"))
    expect(report.warnings).to include("handler exploded")
  end
end
