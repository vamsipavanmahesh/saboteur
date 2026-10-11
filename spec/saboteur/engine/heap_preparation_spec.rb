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
  let(:boot) { instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil) }
  let(:selection) do
    instance_double(Saboteur::Engine::SubjectSelection, select: [subject_under_test], changed_lines: nil)
  end
  let(:store) { instance_double(Saboteur::Engine::CoverageStore, fetch: map) }

  # Runs the engine with the world stubbed away, recording when the heap is
  # prepared relative to the distribution of work. jobs: serial or parallel.
  def run_engine(jobs:, events:)
    stub_boot_phase
    stub_test_phase(events)
    described_class.new(Saboteur::Config.new({ "jobs" => jobs }, root: @root), err: StringIO.new).call
  end

  def stub_boot_phase
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
  end

  def stub_test_phase(events)
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap) { events << :prepare }
    distribution = instance_double(Saboteur::Engine::Distribution)
    allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)
    allow(distribution).to receive(:run) { events << :distribute and [] }
  end

  it "prepares once, before work is distributed, on the parallel path" do
    events = []
    run_engine(jobs: 4, events: events)
    expect(events).to eq(%i[prepare distribute])
  end

  it "prepares once, before work is distributed, on the serial path" do
    events = []
    run_engine(jobs: 1, events: events)
    expect(events).to eq(%i[prepare distribute])
  end
end
