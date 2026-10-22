# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# The engine must prepare the heap once per run, after the coverage map and
# candidate lists are retained and before the execution phase forks, on the
# serial path and on the parallel path alike.
RSpec.describe Saboteur::Engine, "heap preparation" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return([{}, {}])
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:subject_under_test) do
    subjects_in("class HeapTarget\n  def m\n    1\n  end\nend\n", name: "heap_target.rb").first
  end
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => ["t1"] } }, tests: ["t1"])
  end
  let(:integration) { instance_double(Saboteur::Integration::RSpec, test_files: []) }

  # Runs the engine with the world stubbed away, recording the order of the
  # run's phases. Returns the candidate lists the engine retained and the
  # arguments Distribution received, so the specs can prove they are the
  # same object.
  def run_engine(jobs:, events:, subjects: [subject_under_test], rails: true)
    box = {}
    stub_boot_phase(events, subjects, rails: rails)
    stub_test_phase(events, box)
    diagnostics_output = StringIO.new
    engine = described_class.new(Saboteur::Config.new({ "jobs" => jobs }, root: @root),
                                 err: diagnostics_output, verbose: true)
    record_candidate_lists(engine, events, box)
    expect_run_diagnostics(engine, subjects, map)
    report = engine.call
    unless subjects.empty?
      expect(diagnostics_output.string).to include("#{Saboteur::Text.counted(subjects.size, 'subject')}, 1 test")
    end
    expect(report.subjects).to eq(subjects)
    expect(report.skipped_subjects).to eq({}) if subjects.empty?
    [box[:lists], box[:run_args]]
  end

  def expect_run_diagnostics(engine, subjects, map)
    return if subjects.empty?

    expect(Saboteur::Engine::ThreadWarnings).to receive(:warn).and_call_original
    expect(engine).to receive(:inform_about_run).with(subjects, map).and_call_original
  end

  def record_candidate_lists(engine, events, box)
    allow(engine).to receive(:candidate_lists).and_wrap_original do |original, *args|
      box[:lists] = original.call(*args)
      events << :candidates_retained
      box[:lists]
    end
  end

  def stub_boot_phase(events, subjects, rails:)
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    rails = rails ? instance_double(Saboteur::Frameworks::Rails) : nil
    if rails
      allow(rails).to receive(:prepare_workers) { events << :rails_prepared }
      allow(rails).to receive(:cleanup_workers) { events << :rails_cleaned }
    end
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: rails)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    selection = instance_double(Saboteur::Engine::SubjectSelection, select: subjects, behavior_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
  end

  def stub_baseline_phase(events)
    baseline = instance_double(Saboteur::Engine::BaselineGuard)
    allow(baseline).to receive(:call) { events << :baseline_checked }
    allow(baseline).to receive(:completed_passes).and_return(2)
    allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(baseline)
  end

  def stub_test_phase(events, box)
    stub_baseline_phase(events)
    store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false)
    allow(store).to receive(:fetch) { events << :map_retained and map }
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap) { events << :prepare }
    distribution = instance_double(Saboteur::Engine::Distribution, memory_report: nil, unreached: [], truncated: [],
                                                                   unverified: [])
    allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
    allow(distribution).to receive(:run) { |*args| box[:run_args] = args and events << :distribute and [] }
  end

  it "prepares after the map and candidates are retained, before distribution, on the parallel path" do
    events = []
    lists, run_args = run_engine(jobs: 4, events: events)
    expect(events).to eq(%i[baseline_checked map_retained candidates_retained rails_prepared prepare
                            distribute rails_cleaned])
    expect(run_args.last).to eq(lists)
  end

  it "prepares after the map and candidates are retained, before distribution, on the serial path" do
    events = []
    lists, run_args = run_engine(jobs: 1, events: events)
    expect(events).to eq(%i[baseline_checked map_retained candidates_retained rails_prepared prepare
                            distribute rails_cleaned])
    expect(run_args.last).to eq(lists)
  end

  it "dispatches only nonempty aligned subject lists and preserves report subject order" do
    uncovered = subjects_in("class Missing\n  def m\n    2\n  end\nend\n").first
    events = []
    lists, run_args = run_engine(jobs: 4, events: events, subjects: [uncovered, subject_under_test])
    expect(lists.first).to be_empty
    expect(run_args.first).to eq([subject_under_test])
    expect(run_args.last).to eq([lists.last])
  end

  it "runs covered work without a Rails adapter" do
    events = []
    _, run_args = run_engine(jobs: 1, events: events, rails: false)
    expect(events).to eq(%i[baseline_checked map_retained candidates_retained prepare distribute])
    expect(run_args.first).to eq([subject_under_test])
  end

  it "does not prepare when no subjects are selected, but still cleans up at the run boundary" do
    events = []
    run_engine(jobs: 4, events: events, subjects: [])
    expect(events).to eq(%i[rails_cleaned])
  end
end
