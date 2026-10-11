# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# The engine must prepare the heap once per run, after the coverage map and
# candidate lists are retained and before the execution phase forks, on the
# serial path and on the parallel path alike.
RSpec.describe Saboteur::Engine, "heap preparation" do
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
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 2 => ["t1"] } }, tests: ["t1"])
  end
  let(:integration) { instance_double(Saboteur::Integration::RSpec, test_files: []) }

  # Runs the engine with the world stubbed away, recording the order of the
  # run's phases. Returns the candidate lists the engine retained and the
  # arguments Distribution received, so the specs can prove they are the
  # same object.
  def run_engine(jobs:, events:, subjects: [subject_under_test])
    box = {}
    stub_boot_phase(events, subjects)
    stub_test_phase(events, box)
    engine = described_class.new(Saboteur::Config.new({ "jobs" => jobs }, root: @root), err: StringIO.new)
    record_candidate_lists(engine, events, box)
    engine.call
    [box[:lists], box[:run_args]]
  end

  def record_candidate_lists(engine, events, box)
    allow(engine).to receive(:candidate_lists).and_wrap_original do |original, *args|
      box[:lists] = original.call(*args)
      events << :candidates_retained
      box[:lists]
    end
  end

  def stub_boot_phase(events, subjects)
    rails = instance_double(Saboteur::Frameworks::Rails)
    allow(rails).to receive(:prepare_workers) { events << :rails_prepared }
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: rails)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    selection = instance_double(Saboteur::Engine::SubjectSelection, select: subjects, changed_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
  end

  def stub_test_phase(events, box)
    store = instance_double(Saboteur::Engine::CoverageStore)
    allow(store).to receive(:fetch) { events << :map_retained and map }
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap) { events << :prepare }
    distribution = instance_double(Saboteur::Engine::Distribution)
    allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
    allow(distribution).to receive(:run) { |*args| box[:run_args] = args and events << :distribute and [] }
  end

  it "prepares after the map and candidates are retained, before distribution, on the parallel path" do
    events = []
    lists, run_args = run_engine(jobs: 4, events: events)
    expect(events).to eq(%i[map_retained rails_prepared candidates_retained prepare distribute])
    expect(run_args.last).to equal(lists)
  end

  it "prepares after the map and candidates are retained, before distribution, on the serial path" do
    events = []
    lists, run_args = run_engine(jobs: 1, events: events)
    expect(events).to eq(%i[map_retained rails_prepared candidates_retained prepare distribute])
    expect(run_args.last).to equal(lists)
  end

  it "does not prepare when no subjects are selected" do
    events = []
    run_engine(jobs: 4, events: events, subjects: [])
    expect(events).to be_empty
  end
end
