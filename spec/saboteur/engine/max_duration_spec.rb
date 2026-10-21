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

  def unreusable_store
    Object.new.tap { |store| def store.reusable?(_files) = false }
  end

  it "refuses a cold coverage build the budget cannot cover, naming the shortfall and remedies (#427)" do
    engine = engine_with({ "max_duration" => 60 }, StringIO.new)
    engine.instance_variable_set(:@run_started, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 55.0)
    expect { engine.send(:refuse_unaffordable_coverage_build, unreusable_store, [], 50.0, 2) }
      .to raise_error(Saboteur::BudgetPhaseTimeout, /\Are-run with --max-duration about \d+s higher/)
  end

  it "admits the build when the budget covers about one more pass (#427)" do
    engine = engine_with({ "max_duration" => 120 }, StringIO.new)
    engine.instance_variable_set(:@run_started, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 55.0)
    expect { engine.send(:refuse_unaffordable_coverage_build, unreusable_store, [], 50.0, 2) }.not_to raise_error
  end

  it "never refuses a reusable coverage map, however tight the budget (#427)" do
    engine = engine_with({ "max_duration" => 56 }, StringIO.new)
    engine.instance_variable_set(:@run_started, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 55.0)
    reusable = Object.new.tap { |store| def store.reusable?(_files) = true }
    expect { engine.send(:refuse_unaffordable_coverage_build, reusable, [], 50.0, 2) }.not_to raise_error
  end

  it "never trips without a configured budget" do
    engine = engine_with({}, StringIO.new)
    expect(engine.send(:budget_exceeded?)).to eq(false)
  end

  it "trips at the exact budget boundary" do
    engine = engine_with({ "max_duration" => 60 }, StringIO.new)
    engine.instance_variable_set(:@run_started, 100.0)
    allow(Process).to receive(:clock_gettime).and_return(160.0)
    expect(engine.send(:budget_exceeded?)).to eq(true)
  end

  it "announces the spent budget only once it is actually spent" do
    err = StringIO.new
    engine = engine_with({ "max_duration" => 60 }, err)
    engine.instance_variable_set(:@run_started, 100.0)
    allow(Process).to receive(:clock_gettime).and_return(120.0)
    expect(engine.send(:budget_exceeded?)).to eq(false)
    expect(err.string).not_to include("--max-duration reached")
  end

  it "reads the monotonic clock explicitly for the budget" do
    engine = engine_with({ "max_duration" => 60 }, StringIO.new)
    engine.instance_variable_set(:@run_started, 100.0)
    allow(Process).to receive(:clock_gettime).and_return(120.0)
    engine.send(:budget_exceeded?)
    expect(Process).to have_received(:clock_gettime).with(Process::CLOCK_MONOTONIC).at_least(:once)
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
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return([{}, {}])
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => ["t1"] } }, tests: ["t1"])
    integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject], behavior_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
    baseline = instance_double(Saboteur::Engine::BaselineGuard, call: nil, completed_passes: 2)
    allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(baseline)
    store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false)
    allow(store).to receive(:fetch).and_return(map)
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
    captured = nil
    distribution = instance_double(Saboteur::Engine::Distribution, memory_report: nil, unreached: [], truncated: [],
                                                                   unverified: [],
                                                                   run: [])
    allow(Saboteur::Engine::Distribution).to receive(:new) do |**keywords|
      captured = keywords[:halt_check]
      distribution
    end

    engine = described_class.new(Saboteur::Config.new({ "max_duration" => 60 }, root: @root), err: StringIO.new)
    anchored = false
    allow(Process).to receive(:clock_gettime) do
      if !anchored
        anchored = true
        100.0
      elsif captured
        161.0
      else
        120.0 # within budget: the pre-dispatch phases must not stop this run
      end
    end
    engine.call

    expect(captured).not_to be_nil
    expect(captured.call).to eq(true)
  end

  it "hands the scheduler the budget deadline and the result cache (#245)" do
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return([{}, {}])
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => ["t1"] } }, tests: ["t1"])
    integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject], behavior_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
    baseline = instance_double(Saboteur::Engine::BaselineGuard, call: nil, completed_passes: 2)
    allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(baseline)
    store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false)
    allow(store).to receive(:fetch).and_return(map)
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
    allow(Saboteur::Engine::Distribution).to receive(:new)
      .and_return(instance_double(Saboteur::Engine::Distribution, memory_report: nil, unreached: [], truncated: [],
                                                                  unverified: [],
                                                                  run: []))
    scheduler_kwargs = nil
    allow(Saboteur::Engine::Scheduler).to receive(:new) { |**keywords| scheduler_kwargs = keywords and :scheduler }

    engine = described_class.new(Saboteur::Config.new({ "max_duration" => 60 }, root: @root), err: StringIO.new)
    allow(Process).to receive(:clock_gettime).and_return(100.0)
    engine.call

    expect(scheduler_kwargs[:deadline]).to eq(160.0)
    expect(scheduler_kwargs).to have_key(:cache)
  end

  it "installs no budget halt check without a configured budget (#245)" do
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return([{}, {}])
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => ["t1"] } }, tests: ["t1"])
    integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject], behavior_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
    baseline = instance_double(Saboteur::Engine::BaselineGuard, call: nil, completed_passes: 2)
    allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(baseline)
    store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false)
    allow(store).to receive(:fetch).and_return(map)
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
    distribution_kwargs = nil
    allow(Saboteur::Engine::Distribution).to receive(:new) do |**keywords|
      distribution_kwargs = keywords
      instance_double(Saboteur::Engine::Distribution, memory_report: nil, unreached: [], truncated: [],
                                                      unverified: [],
                                                      run: [])
    end
    engine = described_class.new(Saboteur::Config.new({}, root: @root), err: StringIO.new)
    engine.call
    expect(distribution_kwargs[:halt_check]).to be_nil
  end

  it "installs the budget check between baseline passes (#245)" do
    guard_keywords = nil
    allow(Saboteur::Engine::BaselineGuard).to receive(:new) do |**keywords|
      guard_keywords = keywords
      instance_double(Saboteur::Engine::BaselineGuard, call: nil, completed_passes: 2)
    end
    integration = instance_double(Saboteur::Integration::RSpec)
    engine = described_class.new(Saboteur::Config.new({ "max_duration" => 60 }, root: @root), err: StringIO.new)
    engine.send(:check_baseline, integration, 2)

    expect(guard_keywords[:between_passes]).to be_a(Method)
  end

  it "reports a budget stop as max_duration even without fail_fast (#245)" do
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return([{}, {}])
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => ["t1"] } }, tests: ["t1"])
    integration = instance_double(Saboteur::Integration::RSpec, test_files: [])
    allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
    boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
    allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
    selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject], behavior_lines: nil)
    allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
    baseline = instance_double(Saboteur::Engine::BaselineGuard, call: nil, completed_passes: 2)
    allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(baseline)
    store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false)
    allow(store).to receive(:fetch).and_return(map)
    allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
    distribution = instance_double(Saboteur::Engine::Distribution, memory_report: nil, unreached: [subject],
                                                                   truncated: [], unverified: [], run: [])
    allow(Saboteur::Engine::Distribution).to receive(:new).and_return(distribution)

    err = StringIO.new
    engine = described_class.new(Saboteur::Config.new({ "max_duration" => 60 }, root: @root), err: err)
    anchored = false
    allow(Process).to receive(:clock_gettime) do
      if anchored
        161.0 # past the budget once the clock is anchored: the run announces the stop
      else
        anchored = true
        100.0
      end
    end
    engine.call

    expect(err.string).to include("--max-duration reached")
    expect(engine.instance_variable_get(:@early_stop).reason).to eq("max_duration")
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

  it "runs no mutant when the clock is exactly at the deadline" do
    deadline = 500.0
    allow(Process).to receive(:clock_gettime).and_return(deadline)
    ran = []
    results = scheduler_with(deadline).send(:run_candidates, [candidate]) { |mutation, _| ran << mutation }
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

RSpec.describe Saboteur::Engine, "mid-subject budget truncation (#245)" do
  it "records early_stop for a truncated subject even when nothing is unreached" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    engine.instance_variable_set(:@budget_announced, true)
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    distribution = instance_double(Saboteur::Engine::Distribution,
                                   unreached: [], truncated: [[subject, 3]], unverified: [])
    engine.send(:record_early_stop, distribution)
    stop = engine.instance_variable_get(:@early_stop)
    expect(stop.reason).to eq("max_duration")
    expect(stop.unreached).to eq([])
    expect(stop.truncated).to eq([{ subject: subject.id, omitted: 3 }])
  end

  it "still records nothing when the selection ran to completion (control)" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    distribution = instance_double(Saboteur::Engine::Distribution, memory_report: nil, unreached: [], truncated: [],
                                                                   unverified: [])
    engine.send(:record_early_stop, distribution)
    expect(engine.instance_variable_get(:@early_stop)).to be_nil
  end
end

RSpec.describe Saboteur::Engine::BaselineGuard, "phase timeout cap (#296)" do
  around do |example|
    Dir.mktmpdir { |root| @root = root and example.run }
  end

  let(:config) { Saboteur::Config.new({ "seed" => 42, "baseline_passes" => 1 }, root: @root) }
  let(:integration) do
    double("adapter", test_files: [], all_tests: [Saboteur::Integration::TestCase.new(id: "t1", file: "spec/a.rb")])
  end
  let(:supervisor) { instance_double(Saboteur::Execution::Supervisor) }

  it "raises BudgetPhaseTimeout when a budget-capped pass hits its shortened deadline (#296)" do
    response = Saboteur::Execution::Supervisor::Result.new(payload: "", exit_status: nil, stopped_by: :timeout,
                                                           detail: "exceeded deadline", runtime: 0.1,
                                                           leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(response)
    guard = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                                full_passes: 1, timeout_cap: ->(timeout) { timeout / 2 })
    expect { guard.call }.to raise_error(Saboteur::BudgetPhaseTimeout,
                                         "the --max-duration budget stopped baseline check 1 " \
                                         "(admitted 1800.0s of the 3600.0s phase timeout)")
  end

  it "fails the baseline when the capped pass stops for a non-timeout reason (memory) even shortened (#296)" do
    response = Saboteur::Execution::Supervisor::Result.new(payload: "", exit_status: nil, stopped_by: :memory,
                                                           detail: "over 512 MB", runtime: 0.1, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(response)
    guard = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                                full_passes: 1, timeout_cap: ->(timeout) { timeout / 2 })
    expect { guard.call }.to raise_error(Saboteur::Error, /the suite stopped/)
  end

  it "fails the baseline when a timeout hits a full-length admission: cap present but not shortening (#296)" do
    response = Saboteur::Execution::Supervisor::Result.new(payload: "", exit_status: nil, stopped_by: :timeout,
                                                           detail: "exceeded deadline", runtime: 0.1,
                                                           leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(response)
    guard = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                                full_passes: 1, timeout_cap: ->(timeout) { timeout })
    expect { guard.call }.to raise_error(Saboteur::Error, /the suite stopped/)
  end

  it "still fails the baseline when a full-length admission times out: the suite, not the budget (control)" do
    response = Saboteur::Execution::Supervisor::Result.new(payload: "", exit_status: nil, stopped_by: :timeout,
                                                           detail: "exceeded deadline", runtime: 0.1,
                                                           leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(response)
    guard = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                                full_passes: 1)
    expect { guard.call }.to raise_error(Saboteur::Error, /the suite stopped/)
  end

  it "caps an admitted pass at the time the budget leaves" do
    contents = JSON.generate(passed: true, executed: ["t1"], failed: [], error: nil)
    response = Saboteur::Execution::Supervisor::Result.new(payload: contents, exit_status: nil, stopped_by: nil,
                                                           detail: "deadline", runtime: 0.1, leftover_pids: [])
    allow(supervisor).to receive(:run).and_return(response)
    guard = described_class.new(config: config, integration: integration, hooks: Saboteur::Hooks.new,
                                supervisor: supervisor, diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new),
                                full_passes: 1, timeout_cap: ->(timeout) { timeout / 2 })
    guard.call
    expect(supervisor).to have_received(:run).with(hash_including(timeout: 1800.0))
  end
end

RSpec.describe Saboteur::Engine, "budget spent before the coverage map (#245)" do
  it "stops before a cold coverage build and marks every selected subject unrun" do
    Dir.mktmpdir do |directory|
      root = File.realpath(directory)
      file = File.join(root, "probe.rb")
      File.write(file, "class Probe; def value; 1; end; end")
      subject = Saboteur::SubjectFinder.new.call(file).subjects.first
      allow(Saboteur::Engine::Boot).to receive(:refuse_recursion!)
      integration = instance_double(Saboteur::Integration::RSpec, test_files: [], all_tests: [])
      boot = instance_double(Saboteur::Engine::Boot, load_target: integration, rails: nil)
      allow(Saboteur::Engine::Boot).to receive(:new).and_return(boot)
      selection = instance_double(Saboteur::Engine::SubjectSelection, select: [subject], behavior_lines: nil)
      allow(Saboteur::Engine::SubjectSelection).to receive(:new).and_return(selection)
      guard = instance_double(Saboteur::Engine::BaselineGuard, completed_passes: 0)
      allow(guard).to receive(:call) { sleep 0.01 }
      allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(guard)
      store = instance_double(Saboteur::Engine::CoverageStore, reusable?: false)
      allow(store).to receive(:fetch)
      allow(Saboteur::Engine::CoverageStore).to receive(:new).and_return(store)

      # The millisecond budget is spent by the baseline phase alone.
      report = described_class.new(Saboteur::Config.new({ "max_duration" => 0.001 }, root: root),
                                   err: StringIO.new).call

      expect(store).not_to have_received(:fetch)
      stop = report.early_stop
      expect(stop.reason).to eq("max_duration")
      expect(stop.unreached).to eq([subject.id])
    end
  end
end

RSpec.describe Saboteur::Engine::BaselineGuard, "max-duration between passes (#245)" do
  around do |example|
    Dir.mktmpdir { |root| @root = root and example.run }
  end

  let(:config) { Saboteur::Config.new({ "seed" => 42, "baseline_passes" => 3 }, root: @root) }
  let(:integration) do
    double("adapter", test_files: [], all_tests: [Saboteur::Integration::TestCase.new(id: "t1", file: "spec/a.rb")])
  end
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

  it "runs every subject when the halt check never fires" do
    subject = subject_with("m")
    mutation = mutation_for(subject)
    row = [Saboteur::MutantResult.new(subject:, mutation:, status: :killed, mutated_source: "x")]
    scheduler = ->(_subject, _list) { row }
    distribution = described_class.new(jobs: 2, scheduler:, diagnostics:, cache: nil, halt_check: -> { false })
    subjects = Array.new(6) { subject }
    lists = Array.new(6) { [[mutation, "text"]] }
    results = distribution.run(subjects, lists)
    expect(results.size).to eq(6)
    expect(distribution.unreached).to be_empty
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

RSpec.describe Saboteur::Engine::Scheduler, "budget-spent verdict checks (#296)" do
  let(:subject_obj) { subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m") }
  let(:mutation) do
    at = subject_obj.file_source.index("1")
    Saboteur::MutationSource::Mutation.new(subject_id: subject_obj.id, operator: "test",
                                           edits: [Saboteur::MutationSource::Edit.new(file: subject_obj.file,
                                                                                      start_byte: at,
                                                                                      end_byte: at + 1,
                                                                                      replacement: "2")])
  end
  let(:plan) do
    described_class::Plan.new(subject: subject_obj, tests: ["t1"], killers: Hash.new(0), slowdown: 1.0, wrapper: nil)
  end
  let(:runner) { instance_double(Saboteur::Execution::Runner) }
  let(:expired) { Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1 }

  def scheduler(deadline, runner:, cache: nil, map: nil)
    described_class.new(config: { "baseline_timeout" => 60, "timeout_factor" => 4, "timeout_min" => 1 },
                        runner: runner, map: map, reevaluator: nil,
                        diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new), cache: cache,
                        deadline: deadline)
  end

  def kill(killed_by: ["t1"], reused: false)
    Saboteur::MutantResult.new(subject: subject_obj, mutation: mutation, status: :killed, mutated_source: "x",
                               killed_by: killed_by, covered_by: ["t1"], reused: reused)
  end

  def outcome(status, runtime: 0.1)
    Saboteur::Execution::Runner::Outcome.new(status: status, runtime: runtime)
  end

  it "marks a named kill unverified without forking the unchanged check, and caches nothing" do
    cache = double("cache")
    allow(cache).to receive(:record)
    allow(runner).to receive(:run)
    results = scheduler(expired, runner: runner, cache: cache).send(:checked, plan, [kill])
    expect(results.map(&:status)).to eq([:unverified])
    expect(results.first.reason).to include("budget is spent")
    expect(runner).not_to have_received(:run)
    expect(cache).not_to have_received(:record)
  end

  it "marks an unnamed kill unverified too (no zero-time fork)" do
    allow(runner).to receive(:run)
    results = scheduler(expired, runner: runner).send(:checked, plan, [kill(killed_by: [])])
    expect(results.map(&:status)).to eq([:unverified])
    expect(runner).not_to have_received(:run)
  end

  it "leaves reused verdicts and survivors as they are" do
    survivor = Saboteur::MutantResult.new(subject: subject_obj, mutation: mutation, status: :survived,
                                          mutated_source: "x")
    results = scheduler(expired, runner: runner).send(:checked, plan, [kill(reused: true), survivor])
    expect(results.map(&:status)).to eq(%i[killed survived])
  end

  it "runs the check while the deadline is open (control)" do
    allow(runner).to receive(:run).and_return(outcome(:survived))
    open_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
    results = scheduler(open_deadline, runner: runner).send(:checked, plan, [kill])
    expect(results.map(&:status)).to eq([:killed])
    expect(runner).to have_received(:run).with(hash_including(text: subject_obj.source))
  end

  it "skips the calibration retry once the budget is spent: no zero-time fork, timeout not detected" do
    allow(runner).to receive(:run)
    result = scheduler(expired, runner: runner).send(:calibrate, plan, mutation, "text", ["t1"], 1.0)
    expect(result.status).to eq(:unverified)
    expect(runner).not_to have_received(:run)
  end

  it "reports a calibration the shrinking budget cut short as unverified, never as a detected timeout" do
    allow(Process).to receive(:clock_gettime).and_return(1000.0)
    allow(runner).to receive(:run).and_return(outcome(:timeout))
    # 5 s left against a 60 s baseline_timeout: the unchanged run times out under the cap.
    result = scheduler(1005.0, runner: runner).send(:calibrate, plan, mutation, "text", ["t1"], 1.0)
    expect(result.status).to eq(:unverified)
    expect(result.message).to include("cut the timeout calibration short")
    expect(runner).to have_received(:run).with(hash_including(timeout: 5.0))
  end

  it "reports a mutant retry the budget cut short as unverified, not detected" do
    allow(Process).to receive(:clock_gettime).and_return(1000.0)
    allow(runner).to receive(:run).and_return(outcome(:survived, runtime: 2.0), outcome(:timeout))
    map = instance_double(Saboteur::Selection::CoverageMap, recorded_runtime: nil)
    # A longer deadline (8 s) beats the original timeout, but only 3 s remain: the retry is shortened.
    result = scheduler(1003.0, runner: runner, map: map).send(:calibrate, plan, mutation, "text", ["t1"], 1.0)
    expect(result.status).to eq(:unverified)
    expect(result.message).to include("cut the mutant retry short")
  end

  it "counts a retry killed inside the admitted window as a kill (control)" do
    allow(Process).to receive(:clock_gettime).and_return(1000.0)
    allow(runner).to receive(:run).and_return(outcome(:survived, runtime: 2.0), outcome(:killed))
    map = instance_double(Saboteur::Selection::CoverageMap, recorded_runtime: nil)
    result = scheduler(1003.0, runner: runner, map: map).send(:calibrate, plan, mutation, "text", ["t1"], 1.0)
    expect(result.status).to eq(:killed)
  end
end

RSpec.describe Saboteur::Engine, "budget-left checks (#296)" do
  it "records an unverified-only stop with a spent budget as budget-partial (#296)" do
    engine = described_class.new(Saboteur::Config.new({ "max_duration" => 1 }), err: StringIO.new)
    engine.instance_variable_set(:@run_started, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 100)
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    distribution = instance_double(Saboteur::Engine::Distribution, memory_report: nil, unreached: [], truncated: [],
                                                                   unverified: [subject])
    engine.send(:record_early_stop, distribution)
    stop = engine.instance_variable_get(:@early_stop)
    expect(stop.reason).to eq("max_duration")
    expect(stop.unreached).to eq([])
    expect(stop.unverified).to eq([subject.id])
  end

  it "records an unverified-only stop without a budget as a flaky-check disagreement (#1167)" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    distribution = instance_double(Saboteur::Engine::Distribution, memory_report: nil, unreached: [], truncated: [],
                                                                   unverified: [subject])
    engine.send(:record_early_stop, distribution)
    expect(engine.instance_variable_get(:@early_stop).reason).to eq("unverified")
  end

  it "names the budget stop even when fail_fast also fired: a truncated list is budget work (#296)" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    distribution = instance_double(Saboteur::Engine::Distribution,
                                   unreached: [subject], truncated: [[subject, 2]], unverified: [])
    engine.send(:record_early_stop, distribution)
    expect(engine.instance_variable_get(:@early_stop).reason).to eq("max_duration")
  end
end

RSpec.describe Saboteur::Engine, "phase timeout cap (#296)" do
  it "caps an admitted phase at the time left in the budget" do
    engine = described_class.new(Saboteur::Config.new({ "max_duration" => 60 }), err: StringIO.new)
    engine.send(:start_budget_clock, 100.0)
    allow(Process).to receive(:clock_gettime).and_return(140.0)
    expect(engine.send(:budget_capped_timeout, 3600)).to eq(20.0)
  end

  it "clamps a spent budget to zero rather than a negative timeout" do
    engine = described_class.new(Saboteur::Config.new({ "max_duration" => 60 }), err: StringIO.new)
    engine.send(:start_budget_clock, 100.0)
    allow(Process).to receive(:clock_gettime).and_return(200.0)
    expect(engine.send(:budget_capped_timeout, 3600)).to eq(0.0)
  end

  it "passes the phase timeout through with no budget (control)" do
    engine = described_class.new(Saboteur::Config.new({}), err: StringIO.new)
    expect(engine.send(:budget_capped_timeout, 3600)).to eq(3600)
  end
end

RSpec.describe Saboteur::Engine, "budget accounting boundaries (#296)" do
  it "abandons with the subject ids and a strictly true verdict once the budget is spent" do
    engine = described_class.new(Saboteur::Config.new({ "max_duration" => 60 }), err: StringIO.new)
    engine.send(:start_budget_clock, 100.0)
    allow(Process).to receive(:clock_gettime).and_return(200.0)
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    expect(engine.send(:abandon_for_budget?, [subject])).to be(true)
    expect(engine.instance_variable_get(:@early_stop).unreached).to eq(["K#m"])
  end

  it "does not abandon while the budget is open (control)" do
    engine = described_class.new(Saboteur::Config.new({ "max_duration" => 60 }), err: StringIO.new)
    engine.send(:start_budget_clock, 100.0)
    allow(Process).to receive(:clock_gettime).and_return(120.0)
    subject = subject_named("class K\n  def m\n    1\n  end\nend\n", "K#m")
    expect(engine.send(:abandon_for_budget?, [subject])).to be(false)
    expect(engine.instance_variable_get(:@early_stop)).to be_nil
  end

  it "stops when any check trips, not only when all do" do
    engine = described_class.new(Saboteur::Config.new({ "fail_fast" => true }), err: StringIO.new)
    ignore_list = instance_double(Saboteur::IgnoreList, accepts?: false)
    survivor = instance_double(Saboteur::MutantResult, survived?: true)
    killed = instance_double(Saboteur::MutantResult, survived?: false)
    stop = engine.send(:stop_checks, ignore_list)
    expect(stop.call([survivor])).to be(true)
    expect(stop.call([killed])).to be(false)
  end
end

RSpec.describe Saboteur::Engine::Scheduler, "budget cap boundaries (#296)" do
  def scheduler_with(deadline)
    described_class.new(config: {}, runner: nil, map: nil, reevaluator: nil,
                        diagnostics: Saboteur::Engine::Diagnostics.new(StringIO.new), deadline: deadline)
  end

  it "clamps a spent budget to exactly zero" do
    allow(Process).to receive(:clock_gettime).and_return(1000.0)
    expect(scheduler_with(999.0).send(:budget_capped, 60.0)).to eq(0.0)
    expect(scheduler_with(1000.0).send(:budget_capped, 60.0)).to eq(0.0)
  end

  it "caps at the remaining time, and passes the timeout through when it fits" do
    allow(Process).to receive(:clock_gettime).and_return(1000.0)
    expect(scheduler_with(1010.0).send(:budget_capped, 60.0)).to eq(10.0)
    expect(scheduler_with(1100.0).send(:budget_capped, 60.0)).to eq(60.0)
  end
end

RSpec.describe Saboteur::Engine::RunBudget, "#budget_capped_timeout (#296)" do
  def budget(started_ago: 0.0, max_duration: 30.0)
    Object.new.extend(described_class).tap do |object|
      object.instance_variable_set(:@run_started, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_ago)
      object.define_singleton_method(:config) { { "max_duration" => max_duration } }
    end
  end

  it "caps a timeout at the time left in the budget, never below zero" do
    expect(budget.send(:budget_capped_timeout, 5.0)).to be <= 5.0
    expect(budget.send(:budget_capped_timeout, 60.0)).to be <= 30.0
    expect(budget.send(:budget_capped_timeout, 5.0)).to be > 0.0
    expect(budget(started_ago: 31.0).send(:budget_capped_timeout, 5.0)).to eq(0.0)
  end

  it "returns the timeout unchanged without a budget" do
    object = Object.new.extend(described_class)
    object.define_singleton_method(:config) { { "max_duration" => nil } }
    expect(object.send(:budget_capped_timeout, 5.0)).to eq(5.0)
  end
end

RSpec.describe Saboteur::Engine::Scheduler, "per-check budget admission (#296)" do
  let(:err) { StringIO.new }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(err) }
  let(:runner) { instance_double(Saboteur::Execution::Runner) }
  let(:cache) { instance_double(Saboteur::Engine::ResultCache) }
  let(:config) { Saboteur::Config.new({}) }
  let(:subject_under_test) { subjects_in("class K\n  def m\n    1\n  end\nend\n").first }

  def scheduler_with(deadline, map: nil)
    described_class.new(config: config, runner: runner, map: map, reevaluator: nil,
                        diagnostics: diagnostics, cache: cache, deadline: deadline)
  end

  def plan
    Saboteur::Engine::Scheduler::Plan.new(subject: subject_under_test, tests: %w[t1], killers: Hash.new(0),
                                          slowdown: 1.0, wrapper: nil)
  end

  def kill
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject_under_test.id, operator: "test",
                                                      edits: [Saboteur::MutationSource::Edit.new(
                                                        file: subject_under_test.file, start_byte: 0, end_byte: 1,
                                                        replacement: "2"
                                                      )])
    Saboteur::MutantResult.new(subject: subject_under_test, mutation: mutation, status: :killed,
                               mutated_source: "2", killed_by: %w[t1], covered_by: %w[t1])
  end

  it "marks a fresh kill unverified without forking once the budget is spent mid-check, and never caches it" do
    times = [100.0, 200.0].each
    allow(Process).to receive(:clock_gettime) { times.next }
    allow(runner).to receive(:run)
    allow(cache).to receive(:record)
    final = scheduler_with(150.0).send(:checked, plan, [kill])
    expect([final.first.status, final.first.reason]).to eq([:unverified, "the --max-duration budget is spent"])
    expect(runner).not_to have_received(:run)
    expect(cache).not_to have_received(:record)
  end

  it "marks a kill unverified when its check only timed out under a budget-shortened cap" do
    allow(Process).to receive(:clock_gettime).and_return(100.0)
    allow(runner).to receive(:run).and_return(Saboteur::Execution::Runner::Outcome.new(status: :timeout,
                                                                                       runtime: 5.0))
    allow(cache).to receive(:record)
    final = scheduler_with(105.0).send(:checked, plan, [kill])
    expect(final.first.status).to eq(:unverified)
    expect(runner).to have_received(:run).with(hash_including(timeout: 5.0))
    expect(cache).not_to have_received(:record)
  end

  it "still caches a kill the unchanged check confirmed (control)" do
    allow(Process).to receive(:clock_gettime).and_return(100.0)
    allow(runner).to receive(:run).and_return(Saboteur::Execution::Runner::Outcome.new(status: :survived,
                                                                                       runtime: 0.1))
    allow(cache).to receive(:record)
    final = scheduler_with(150.0).send(:checked, plan, [kill])
    expect(final.first.status).to eq(:killed)
    expect(cache).to have_received(:record)
  end

  it "warns about genuine rejections only, not unverified checks" do
    allow(Process).to receive(:clock_gettime).and_return(100.0)
    allow(runner).to receive(:run).and_return(Saboteur::Execution::Runner::Outcome.new(status: :killed,
                                                                                       runtime: 0.1,
                                                                                       message: "boom"))
    allow(cache).to receive(:record)
    map = instance_double(Saboteur::Selection::CoverageMap, tests: [])
    final = scheduler_with(150.0, map: map).send(:checked, plan, [kill])
    expect(final.first.status).to eq(:error)
    expect(diagnostics.warnings).to include("#{subject_under_test.id}: 1 verdict(s) failed with the method unchanged")
  end

  it "does not fork the mutant retry once the unchanged timing used the final allowance" do
    times = [100.0, 100.0, 200.0].each
    allow(Process).to receive(:clock_gettime) { times.next }
    allow(runner).to receive(:run).and_return(Saboteur::Execution::Runner::Outcome.new(status: :survived,
                                                                                       runtime: 2.0))
    map = instance_double(Saboteur::Selection::CoverageMap, recorded_runtime: 1.0)
    outcome = scheduler_with(150.0, map: map).send(:calibrate, plan, kill.mutation, "text", %w[t1], 0.5)
    expect(outcome.status).to eq(:unverified)
    expect(outcome.message).to include("spent before the mutant retry")
    expect(runner).to have_received(:run).once
  end
end
