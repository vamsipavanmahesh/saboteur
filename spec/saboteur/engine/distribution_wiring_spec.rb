# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"
require "json"

# The engine hands its cache and callbacks to Distribution. Drop one of the
# pairs and a run still completes, but pooled workers skip their start
# hooks, the canary never checks the tree, or the result cache stays empty.
RSpec.describe Saboteur::Engine, "distribution wiring" do
  around do |example|
    Dir.mktmpdir("saboteur-wiring-") { |dir| @root = File.realpath(dir) and example.run }
  end

  let(:subject_under_test) do
    subjects_in("class WireTarget\n  def value(a)\n    a + 1\n  end\nend\n", name: "wire_target.rb").first
  end
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => ["t1"] } }, tests: ["t1"])
  end

  def wired_engine(config_values, scheduler:)
    stub_front_end
    allow(Saboteur::Engine::Scheduler).to receive(:new).and_return(scheduler)
    described_class.new(Saboteur::Config.new(config_values, root: @root), err: StringIO.new)
  end

  # The pipeline up to Distribution: boot, subject selection, the coverage
  # store and the baseline check. Everything after them runs for real.
  def stub_front_end
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    # Reading load-time coverage would suspend the recorder mid-build when
    # the dogfood's coverage pass runs this spec; the wiring tested here is
    # downstream of boot.
    allow_any_instance_of(described_class).to receive(:suspend_coverage).and_return([{}, {}])
    stub_boot
    stub_selection_and_store
  end

  def stub_boot
    boot = instance_double(Saboteur::Engine::Boot, load_target: double("integration", test_files: []), rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    guard = instance_double(Saboteur::Engine::BaselineGuard, call: nil, completed_passes: 2)
    allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(guard)
  end

  def stub_selection_and_store
    selection = instance_double(Saboteur::Engine::SubjectSelection,
                                select: [subject_under_test], changed_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
    store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false, fetch: map)
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
  end

  # One killed result per candidate; the optional block runs first, inside
  # whichever process the scheduler runs in.
  def canned_scheduler(&before)
    lambda do |subject, list|
      before&.call
      list.map do |mutation, text|
        Saboteur::MutantResult.new(subject: subject, mutation: mutation, status: :killed, mutated_source: text,
                                   runtime: 0.1, covered_by: ["t1"], killed_by: ["t1"])
      end
    end
  end

  it "checks the tree after each subject: a mutant that deletes a watched file trips the canary" do
    sentinel = File.join(@root, "sentinel.txt")
    File.write(sentinel, "x")
    engine = wired_engine({ "jobs" => 1 }, scheduler: canned_scheduler { FileUtils.rm_f(sentinel) })
    expect { engine.call }.to raise_error(Saboteur::CanaryTripped, /sentinel\.txt/)
  end

  it "starts pooled workers through start_worker: worker_start hooks run with their number" do
    marks = File.join(@root, "workers.txt")
    engine = wired_engine({ "jobs" => 2 }, scheduler: canned_scheduler)
    engine.hooks.register(:worker_start) { |number| File.open(marks, "a") { |file| file.puts(number) } }
    engine.call
    expect(File.readlines(marks).map(&:strip)).not_to be_empty
  end

  it "prints each finished subject's result marks when --verbose is on (#262)" do
    stub_front_end
    err = StringIO.new
    allow(Saboteur::Engine::Scheduler).to receive(:new).and_return(canned_scheduler)
    engine = described_class.new(Saboteur::Config.new({ "jobs" => 1 }, root: @root), err: err, verbose: true)
    engine.call
    expect(err.string).to include("WireTarget#value  .")
  end

  it "keeps per-subject marks out of the output without --verbose" do
    stub_front_end
    err = StringIO.new
    allow(Saboteur::Engine::Scheduler).to receive(:new).and_return(canned_scheduler)
    engine = described_class.new(Saboteur::Config.new({ "jobs" => 1 }, root: @root), err: err)
    engine.call
    expect(err.string).not_to include("WireTarget#value  .")
  end

  it "records pooled results into the incremental result cache" do
    cache_dir = File.join(@root, "cache")
    engine = wired_engine({ "jobs" => 2, "incremental" => true, "cache_dir" => cache_dir },
                          scheduler: canned_scheduler)
    engine.call
    data = JSON.parse(File.read(File.join(cache_dir, "results.json")))
    expect(data["entries"]).not_to be_empty
  end
end
