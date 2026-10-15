# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine, "--max-duration budget (#245)" do
  def engine_with(config_values, err)
    described_class.new(Saboteur::Config.new(config_values, root: Dir.mktmpdir), err: err)
  end

  # The clock is anchored at Engine#call entry, not lazily at the first
  # check, so boot and baselines spend the budget too.
  it "measures the budget from the anchored run start and trips once it passes, announcing once" do
    err = StringIO.new
    engine = engine_with({ "max_duration" => 60 }, err)
    engine.instance_variable_set(:@run_started, 100.0)
    times = [150.0, 161.0, 200.0].each
    allow(Process).to receive(:clock_gettime) { times.next }

    expect(engine.send(:budget_exceeded?)).to eq(false)
    expect(engine.send(:budget_exceeded?)).to eq(true)
    expect(engine.send(:budget_exceeded?)).to eq(true)
    expect(err.string.scan("--max-duration reached").size).to eq(1)
  end

  it "never trips without a configured budget" do
    engine = engine_with({}, StringIO.new)
    expect(engine.send(:budget_exceeded?)).to eq(false)
  end

  it "hands the schedulers an absolute deadline from the anchored start" do
    engine = engine_with({ "max_duration" => 60 }, StringIO.new)
    engine.instance_variable_set(:@run_started, 100.0)
    expect(engine.send(:budget_deadline)).to eq(160.0)
  end
end

RSpec.describe Saboteur::Engine, "--max-duration wiring (#245)" do
  around do |example|
    Dir.mktmpdir { |root| @root = File.realpath(root) and example.run }
  end

  # The halt check handed to the distribution must measure from engine
  # entry: with the run started at 100 and the budget 60, a check at 161
  # trips. A lazy first-check clock would start at the check itself.
  it "anchors the budget clock at call entry, before boot and baselines" do
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return({})
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => ["t1"] } }, tests: ["t1"])
    integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject], changed_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
    baseline = instance_double(Saboteur::Engine::BaselineGuard, call: nil, completed_passes: 2)
    allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(baseline)
    store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false)
    allow(store).to receive(:fetch).and_return(map)
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
    captured = nil
    distribution = instance_double(Saboteur::Engine::Distribution, unreached: [], run: [])
    allow(Saboteur::Engine::Distribution).to receive(:new) do |**keywords|
      captured = keywords[:halt_check]
      distribution
    end

    engine = described_class.new(Saboteur::Config.new({ "max_duration" => 60 }, root: @root), err: StringIO.new)
    times = ([100.0] + Array.new(50, 161.0)).each
    allow(Process).to receive(:clock_gettime) { times.next }
    engine.call

    expect(captured).not_to be_nil
    expect(captured.call).to eq(true)
  end
end

RSpec.describe Saboteur::Engine::Scheduler, "max-duration deadline (#245)" do
  def scheduler_with(deadline)
    described_class.new(config: {}, runner: nil, map: nil, reevaluator: nil,
                        diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new), deadline: deadline)
  end

  def candidate(coarse: false)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: "K#m", operator: "test",
                                                      edits: [Saboteur::MutationSource::Edit.new(
                                                        file: "k.rb", start_byte: 0, end_byte: 1, replacement: "2"
                                                      )], coarse: coarse)
    [mutation, "text"]
  end

  it "runs no mutant once the deadline has passed" do
    ran = []
    results = scheduler_with(Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
              .send(:run_candidates, [candidate, candidate(coarse: true)]) { |mutation, _| ran << mutation }
    expect(results).to eq([])
    expect(ran).to eq([])
  end

  it "runs coarse before fine while the deadline is open" do
    ran = []
    results = scheduler_with(Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60)
              .send(:run_candidates, [candidate, candidate(coarse: true)]) { |mutation, _| (ran << mutation) && :ok }
    expect(results).to eq(%i[ok ok])
    expect(ran.map(&:coarse)).to eq([true, false])
  end
end

RSpec.describe Saboteur::Engine::BaselineGuard, "max-duration between passes (#245)" do
  around do |example|
    Dir.mktmpdir { |root| @root = root and example.run }
  end

  let(:config) { Saboteur::Config.new({ "seed" => 42, "baseline_passes" => 3 }, root: @root) }
  let(:integration) { double("adapter", all_tests: [Saboteur::Integration::TestCase.new(id: "t1", file: "spec/a.rb")]) }
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }

  def response
    contents = JSON.generate(passed: true, executed: ["t1"], failed: [], error: nil)
    Saboteur::Execution::Supervisor::Result.new(payload: contents, exit_status: nil, stopped_by: nil,
                                                detail: "deadline", runtime: 0.1, leftover_pids: [])
  end

  it "skips the remaining passes when the budget check trips between passes, and counts only completed ones" do
    allow(supervisor).to receive(:run).and_return(response)
    checks = 0
    guard = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                                full_passes: 3, between_passes: -> { (checks += 1) > 1 })
    guard.call
    expect(supervisor).to have_received(:run).once
    expect(guard.completed_passes).to eq(1)
  end

  it "starts no baseline at all when the budget is already spent at entry (boot admission)" do
    allow(supervisor).to receive(:run).and_return(response)
    guard = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                                full_passes: 3, between_passes: -> { true })
    guard.call
    expect(supervisor).not_to have_received(:run)
    expect(guard.completed_passes).to eq(0)
  end

  it "runs every pass while the budget check stays open" do
    allow(supervisor).to receive(:run).and_return(response)
    guard = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                                full_passes: 3, between_passes: -> { false })
    guard.call
    expect(supervisor).to have_received(:run).exactly(3).times
    expect(guard.completed_passes).to eq(3)
  end
end

RSpec.describe Saboteur::Engine::Distribution, "max-duration halt (#245)" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }

  def mutation_for(subject)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: subject.file_source.index("1"),
                                              end_byte: subject.file_source.index("1") + 1, replacement: "2")
    Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
  end

  def subject_with(name)
    subject_named("class K\n  def #{name}\n    1\n  end\nend\n", "K##{name}")
  end

  it "halts the pool when the check fires, lets in-flight subjects finish, and leaves unstarted ones unreached" do
    subject = subject_with("m")
    mutation = mutation_for(subject)
    # The pre-dispatch check consumes the first tick; the first arrival's
    # check then trips the halt.
    ticks = [false, false, true].cycle
    halt_check = -> { ticks.next }
    subjects = Array.new(6) { subject }
    lists = Array.new(6) { [[mutation, "text"]] }
    row = [Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "x")]
    scheduler = ->(_subject, _list) { row }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil, halt_check: halt_check)
    results = distribution.run(subjects, lists)
    expect(results.map(&:status)).to all(eq(:killed))
    expect(distribution.unreached).not_to be_empty
    expect(distribution.unreached.size).to be < 6
    expect(results.size + distribution.unreached.size).to eq(6)
  end

  it "launches no subject when the budget is already spent, serial" do
    subject = subject_with("m")
    ran = []
    distribution = described_class.new(jobs: 1, scheduler: lambda { |s, _l|
      ran << s
      []
    }, diagnostics:, cache: nil,
                                       halt_check: -> { true })
    subjects = [subject, subject]
    lists = [[], []]
    expect(distribution.run(subjects, lists)).to eq([])
    expect(ran).to eq([])
    expect(distribution.unreached).to eq(subjects)
  end

  it "launches no subject when the budget is already spent, parallel" do
    subject = subject_with("m")
    ran = []
    distribution = described_class.new(jobs: 2, scheduler: lambda { |s, _l|
      ran << s
      []
    }, diagnostics:, cache: nil,
                                       halt_check: -> { true })
    subjects = [subject, subject, subject]
    lists = [[], [], []]
    expect(distribution.run(subjects, lists)).to eq([])
    expect(ran).to eq([])
    expect(distribution.unreached).to eq(subjects)
  end

  # A slow in-flight subject outlives the safety drain timeout: the budget
  # halt still waits for it, so its completed mutants are recorded and only
  # the never-started subject is unreached.
  it "finishes an in-flight subject past the drain deadline instead of killing it" do
    slow = subject_with("slow")
    fast = subject_with("fast")
    queued = subject_with("queued")
    mutations = {}
    [slow, fast, queued].each { |subject| mutations[subject.id] = mutation_for(subject) }
    rows = {}
    [slow, fast, queued].each do |subject|
      rows[subject.id] = [Saboteur::MutantResult.new(subject:, mutation: mutations.fetch(subject.id),
                                                     status: :killed, mutated_source: "x")]
    end
    scheduler = lambda do |subject, _list|
      sleep(1.5) if subject.id == "K#slow"
      rows.fetch(subject.id)
    end
    # First tick: the pre-dispatch check. The first arrival's check trips
    # the halt, so the queued subject never starts; the slow subject is
    # already in flight.
    ticks = [false, true].cycle
    halt_check = -> { ticks.next }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil, halt_check: halt_check,
                                       drain_timeout: 0.2)
    # The slow subject's large candidate list sorts it into the first wave.
    slow_mutations = Array.new(8) { mutations.fetch("K#slow") }
    subjects = [slow, fast, queued]
    lists = [slow_mutations.map { |m| [m, "text"] }, [[mutations.fetch("K#fast"), "text"]],
             [[mutations.fetch("K#queued"), "text"]]]
    results = distribution.run(subjects, lists)
    expect(results.map(&:subject)).to include(slow)
    expect(results.map(&:subject)).to include(fast)
    expect(distribution.unreached).to eq([queued])
  end
end
