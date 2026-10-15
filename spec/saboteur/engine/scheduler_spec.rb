# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine::Scheduler do
  describe ".prioritize" do
    it "puts tests that killed earlier mutants first and keeps the given order otherwise" do
      expect(described_class.prioritize(%w[fast mid slow other], { "slow" => 2, "mid" => 1 }))
        .to eq(%w[slow mid fast other])
    end
  end
end

# A kill is only real if the killing test passes when the method is
# re-evaluated unchanged; a timeout only if the unchanged method finishes in
# time. So the scheduler re-runs the evidence, not the whole suite: a method
# that every factory calls can have hundreds of tests and a handful of killers.
RSpec.describe Saboteur::Engine::Scheduler, "verifying kills and timeouts" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:subject_under_test) { subjects_in("class SchedulerTarget\n  def m(a)\n    a + 1\n  end\nend\n").first }
  let(:durations) { { "t1" => 0.1, "t2" => 0.1 } }
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => %w[t1 t2] } },
                                         tests: %w[t1 t2], durations: durations)
  end
  let(:candidates) { Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics) }
  let(:runner) { instance_double(Saboteur::Execution::Runner) }

  # mutant: the outcome of every mutant run, given its mutation.
  # unchanged: the outcome of a run of the unchanged method, given its tests.
  def schedule(mutant:, unchanged: ->(_tests) { outcome(:survived) })
    allow(runner).to receive(:run) do |test_ids:, mutation: nil, **|
      mutation ? mutant.call(mutation) : unchanged.call(test_ids)
    end
    scheduler.call(subject_under_test, candidates.for(subject_under_test))
  end

  def scheduler
    described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                        reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics).tap do |s|
      allow(s).to receive(:load_problem).and_return(nil)
    end
  end

  def outcome(status, failed_ids: [], runtime: 1.0, message: nil)
    Saboteur::Execution::Runner::Outcome.new(status: status, runtime: runtime, failed_ids: failed_ids, message: message)
  end

  def unchanged_runs
    calls = []
    expect(runner).to have_received(:run).at_least(:once) do |test_ids:, mutation: nil, **|
      calls << test_ids unless mutation
    end
    calls
  end

  # >=, not >: at the exact deadline no further check may fork (#296).
  it "counts the budget as spent at the exact deadline, not only past it (#296)" do
    sched = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics,
                                deadline: 100.0)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(99.9)
    expect(sched.send(:budget_spent?)).to be(false)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.0)
    expect(sched.send(:budget_spent?)).to be(true)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(100.1)
    expect(sched.send(:budget_spent?)).to be(true)
  end

  it "runs no mutant-free check before the mutants" do
    schedule(mutant: ->(_) { outcome(:survived) })
    expect(unchanged_runs).to be_empty
  end

  it "re-runs each kill's own tests up to the killer, once per distinct sequence" do
    results = schedule(mutant: ->(_) { outcome(:killed, failed_ids: ["t2"]) })
    expect(results.map(&:status).uniq).to eq([:killed])
    # The first mutant ran t1 then t2; later ones put the killer t2 first.
    expect(unchanged_runs).to contain_exactly(%w[t1 t2], ["t2"])
  end

  # The budget can run out mid-check: the first sequence's re-run proves
  # its kills, the next never forks - its kills become unverified, naming
  # the budget as the reason, and nothing unproven is cached (#296).
  it "leaves later-sequence kills unverified, naming the budget, when it runs out mid-check (#296)" do
    store = instance_double(Saboteur::Engine::ResultCache, record: nil, lookup: nil)
    sched = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics,
                                cache: store)
    allow(sched).to receive(:load_problem).and_return(nil)
    first_mutant = true
    unchanged_ran = false
    allow(runner).to receive(:run) do |mutation: nil, **|
      if mutation
        killer = first_mutant ? "t1" : "t2"
        first_mutant = false
        outcome(:killed, failed_ids: [killer])
      else
        unchanged_ran = true
        outcome(:survived)
      end
    end
    allow(sched).to receive(:budget_spent?) { unchanged_ran }
    results = sched.call(subject_under_test, candidates.for(subject_under_test))
    expect(results.map(&:status).uniq).to contain_exactly(:killed, :unverified)
    unverified = results.find { |result| result.status == :unverified }
    expect(unverified.reason).to eq("the --max-duration budget is spent")
    expect(store).to have_received(:record).with(kind_of(Saboteur::MutantResult)).at_least(:once)
    expect(store).not_to have_received(:record).with(having_attributes(status: :unverified))
    expect(diagnostics.warnings.grep(/verdict.*failed/)).to be_empty
  end

  # A verdict check timing out at a timeout the budget did not shorten is a
  # real rejected kill, not a budget artifact (#296).
  it "rejects a kill whose unchanged check times out at a full-length timeout (#296)" do
    results = schedule(mutant: ->(_) { outcome(:killed, failed_ids: ["t1"]) },
                       unchanged: ->(_) { outcome(:timeout, runtime: 5.0) })
    expect(results.map(&:status).uniq).to eq([:error])
    expect(results.first.rejected_kill?).to be(true)
  end

  it "warns exactly once per verdict overturned by the unchanged re-run (#296)" do
    io = StringIO.new
    diagnostics = Saboteur::Engine::Diagnostics.new(io)
    sched = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics)
    allow(sched).to receive(:load_problem).and_return(nil)
    allow(runner).to receive(:run) { |**| outcome(:killed, failed_ids: ["t1"]) }
    results = sched.call(subject_under_test, candidates.for(subject_under_test))
    expect(results.map(&:status).uniq).to eq([:error])
    overturned = results.size
    expect(diagnostics.warnings)
      .to include("#{subject_under_test.id}: #{overturned} verdict(s) failed with the method unchanged")
  end

  it "does not warn when no verdict was overturned (#296)" do
    io = StringIO.new
    diagnostics = Saboteur::Engine::Diagnostics.new(io)
    sched = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics)
    allow(sched).to receive(:load_problem).and_return(nil)
    allow(runner).to receive(:run) do |mutation: nil, **|
      mutation ? outcome(:killed, failed_ids: ["t1"]) : outcome(:survived)
    end
    sched.call(subject_under_test, candidates.for(subject_under_test))
    expect(diagnostics.warnings.grep(/verdict.*failed/)).to be_empty
  end

  it "never re-records a verdict the cache already had, however the check goes (#296)" do
    store = instance_double(Saboteur::Engine::ResultCache, record: nil)
    allow(store).to receive(:lookup).and_return({ status: :killed, reason: "cached", runtime: 0.2,
                                                  killed_by: ["t1"], kill_cause: "assertion" })
    sched = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics,
                                cache: store)
    allow(sched).to receive(:load_problem).and_return(nil)
    results = sched.call(subject_under_test, candidates.for(subject_under_test))
    expect(results.map(&:reused?).uniq).to eq([true])
    expect(store).not_to have_received(:record)
  end

  it "does not count a pre-existing error as an overturned verdict (#296)" do
    allow(runner).to receive(:run) { |**| outcome(:error, message: "child crashed") }
    results = schedule(mutant: ->(_) { outcome(:error, message: "child crashed") })
    expect(results.map(&:status).uniq).to eq([:error])
    expect(diagnostics.warnings.grep(/verdict.*failed/)).to be_empty
  end

  it "names the shortened cap when a kill's unchanged check times out at it (#296)" do
    sched = scheduler
    allow(sched).to receive(:budget_capped).and_return(0.5)
    allow(runner).to receive(:run) do |mutation: nil, **|
      mutation ? outcome(:killed, failed_ids: ["t1"]) : outcome(:timeout, runtime: 0.5)
    end
    results = sched.call(subject_under_test, candidates.for(subject_under_test))
    expect(results.map(&:status).uniq).to eq([:unverified])
    expect(results.first.reason).to eq("the --max-duration budget cut the verdict check short")
  end

  it "names the budget when a timeout's calibration cannot start (#296)" do
    sched = scheduler
    mutant_ran = false
    allow(runner).to receive(:run) do |mutation: nil, **|
      if mutation
        mutant_ran = true
        outcome(:timeout, runtime: 5.0)
      else
        outcome(:survived)
      end
    end
    allow(sched).to receive(:budget_spent?) { mutant_ran }
    results = sched.call(subject_under_test, candidates.for(subject_under_test))
    expect(results.map(&:status).uniq).to eq([:unverified])
    expect(results.first.reason).to eq("timeout calibration skipped: the --max-duration budget is spent")
  end

  it "names the budget when it runs out between the unchanged timing and the retry (#296)" do
    sched = scheduler
    unchanged_ran = false
    allow(runner).to receive(:run) do |mutation: nil, **|
      if mutation
        outcome(:timeout, runtime: 5.0)
      else
        unchanged_ran = true
        outcome(:survived, runtime: 10.0)
      end
    end
    allow(sched).to receive(:budget_spent?) { unchanged_ran }
    results = sched.call(subject_under_test, candidates.for(subject_under_test))
    expect(results.map(&:status).uniq).to eq([:unverified])
    expect(results.first.reason).to eq("the --max-duration budget is spent before the mutant retry")
  end

  # A retry at its full longer timeout that still times out is the mutant's
  # own; one cut short by the budget proves nothing (#296).
  it "counts a budget-cut retry as unverified, but a full-length retry timeout as the mutant's own (#296)" do
    sched = scheduler
    allow(runner).to receive(:run) do |mutation: nil, **|
      mutation ? outcome(:timeout, runtime: 5.0) : outcome(:survived, runtime: 10.0)
    end
    allow(sched).to receive(:budget_capped) { |timeout| timeout > 100 ? timeout : 0.5 }
    results = sched.call(subject_under_test, candidates.for(subject_under_test))
    expect(results.map(&:status)).to include(:unverified)
    cut = results.select { |result| result.status == :unverified }
    expect(cut.map(&:reason).uniq).to eq(["the --max-duration budget cut the mutant retry short"])

    uncapped = scheduler
    allow(runner).to receive(:run) do |mutation: nil, **|
      mutation ? outcome(:timeout, runtime: 5.0) : outcome(:survived, runtime: 10.0)
    end
    allow(uncapped).to receive(:budget_capped) { |timeout| timeout }
    retried = uncapped.call(subject_under_test, candidates.for(subject_under_test))
    expect(retried.map(&:status).uniq).to eq([:timeout])
  end

  it "names the timeout check when it kills processes a run left behind (#296)" do
    schedule(mutant: ->(_) { outcome(:timeout, runtime: 5.0) },
             unchanged: lambda { |_|
               Saboteur::Execution::Runner::Outcome.new(status: :survived, runtime: 0.1,
                                                        leftover_pids: ["999"])
             })
    expect(diagnostics.warnings)
      .to include("#{subject_under_test.id} timeout check: killed 1 process(es) it left running")
  end

  it "turns a kill into an error when the killing test also fails with the method unchanged" do
    results = schedule(mutant: ->(_) { outcome(:killed, failed_ids: ["t1"]) },
                       unchanged: ->(_) { outcome(:killed, failed_ids: ["t1"]) })
    expect(results.map(&:status).uniq).to eq([:error])
    expect(results.first.reason).to eq("killing test t1 also fails with the method unchanged")
  end

  it "says why the killing test failed with the method unchanged" do
    results = schedule(mutant: ->(_) { outcome(:killed, failed_ids: ["t1"]) },
                       unchanged: ->(_) { outcome(:killed, failed_ids: ["t1"], message: "relation does not exist") })
    expect(results.first.reason).to eq("killing test t1 also fails with the method unchanged: relation does not exist")
  end

  # t2 fails only when t1 ran before it in the same process.
  it "turns a kill into an error when the killer fails only after the tests that ran before it" do
    order_dependent = ->(tests) { tests == %w[t1 t2] ? outcome(:killed, failed_ids: ["t2"]) : outcome(:survived) }
    results = schedule(mutant: ->(_) { outcome(:killed, failed_ids: ["t2"]) }, unchanged: order_dependent)
    by_sequence = results.group_by { |result| result.covered_by.first(result.covered_by.index("t2") + 1) }
    expect(by_sequence.transform_values { |group| group.map(&:status).uniq })
      .to eq({ %w[t1 t2] => [:error], ["t2"] => [:killed] })
  end

  # Recorded durations come from one warm process; a fresh child can be
  # slower. A timeout is checked on the spot against the real runtime of the
  # unchanged method.
  describe "a timed-out mutant" do
    it "keeps the timeout when the unchanged method runs well inside the deadline" do
      results = schedule(mutant: ->(_) { outcome(:timeout) })
      expect(results.map(&:status).uniq).to eq([:timeout])
    end

    it "runs again with a deadline from the unchanged method's real runtime" do
      allow(runner).to receive(:run) do |test_ids:, timeout:, mutation: nil, **|
        if mutation then timeout < 30 ? outcome(:timeout) : outcome(:killed, failed_ids: [test_ids.first])
        else outcome(:survived, runtime: 10.0)
        end
      end
      results = scheduler.call(subject_under_test, candidates.for(subject_under_test))
      expect(results.map(&:status).uniq).to eq([:killed])
      expect(runner).to have_received(:run).with(hash_including(timeout: 30.0)).at_least(:once)
    end

    it "gives later mutants of the subject the measured slowdown" do
      measured = 0
      allow(runner).to receive(:run) do |test_ids:, timeout:, mutation: nil, **|
        next outcome(timeout < 30 ? :timeout : :survived) if mutation

        measured += 1 if test_ids.size == 2 && timeout == 300
        outcome(:survived, runtime: 10.0)
      end
      scheduler.call(subject_under_test, candidates.for(subject_under_test))
      expect(measured).to eq(1)
    end

    it "is an error when the unchanged method times out too" do
      results = schedule(mutant: ->(_) { outcome(:timeout) }, unchanged: ->(_) { outcome(:timeout) })
      expect(results.map(&:status).uniq).to eq([:error])
      expect(results.first.reason).to eq("tests also time out with the method unchanged (raise baseline_timeout)")
    end
  end

  context "with slow tests" do
    let(:durations) { { "t1" => 3.0, "t2" => 4.0 } }

    it "gives each mutant a timeout of timeout_factor times its tests' recorded durations" do
      schedule(mutant: ->(_) { outcome(:survived) })
      expect(runner).to have_received(:run).with(hash_including(timeout: 21.0)).at_least(:once)
    end
  end

  it "never gives a mutant less than timeout_min" do
    schedule(mutant: ->(_) { outcome(:survived) })
    expect(runner).to have_received(:run).with(hash_including(timeout: 5.0)).at_least(:once)
  end
end

RSpec.describe Saboteur::Engine::Scheduler, "coarse-first execution" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }

  def results_for(source)
    subject = subjects_in(source).first
    lines = (subject.start_line..subject.end_line).to_h { |line| [line, ["t1"]] }
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => lines }, tests: ["t1"])
    runner = instance_double(Saboteur::Execution::Runner)
    allow(runner).to receive(:run).and_return(Saboteur::Execution::Runner::Outcome.new(status: :survived, runtime: 0.1))
    scheduler = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                    reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics)
    allow(scheduler).to receive(:load_problem).and_return(nil)
    candidates = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics)
    scheduler.call(subject, candidates.for(subject))
  end

  it "runs fine mutants when a coarse mutant survives in a plain method" do
    results = results_for("class K\n  def m(a)\n    b = a + 1\n    b * 2\n  end\nend\n")
    expect(results.reject { |result| result.mutation.coarse }).not_to be_empty
    expect(results).to all(have_attributes(status: :survived))
  end

  it "still runs fine mutants when the method has a rescue: the rescue may return what fine mutants expose" do
    reasons = results_for("class K\n  def m(a)\n    b = a + 1\n    b * 2\n  rescue ArgumentError\n    0\n  end\nend\n")
              .map(&:reason)
    expect(reasons).not_to include("coarse mutant survived")
  end
end

RSpec.describe Saboteur::Engine::Scheduler, "result cache" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:subject_under_test) { subjects_in("class K\n  def m(a)\n    b = a + 1\n    b * 2\n  end\nend\n").first }
  let(:map) do
    lines = (2..5).to_h { |line| [line, ["t1"]] }
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => lines }, tests: ["t1"])
  end
  let(:runner) { instance_double(Saboteur::Execution::Runner) }

  def cache
    Saboteur::Engine::ResultCache.new(path: File.join(@root, "results.json"), root: @root, inputs: "x")
  end

  def run_with(store)
    scheduler = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                    reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics,
                                    cache: store)
    allow(scheduler).to receive(:load_problem).and_return(nil)
    candidates = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics)
    scheduler.call(subject_under_test, candidates.for(subject_under_test)).tap { store&.save }
  end

  before do
    allow(runner).to receive(:run) do |**args|
      status = args[:mutation].nil? || !args[:mutation].coarse ? :survived : :killed
      Saboteur::Execution::Runner::Outcome.new(status: status, runtime: 0.1,
                                               failed_ids: status == :killed ? ["t1"] : [])
    end
  end

  it "forks nothing, not even the neutral check, when every verdict is reusable" do
    first = run_with(cache)
    second = run_with(cache)
    expect(runner).to have_received(:run).exactly(first.size + 1).times
    expect(second.map(&:status)).to eq(first.map(&:status))
    expect(second).to all(be_reused)
  end

  it "still forks nothing when a fine mutant has no covering test (it is skipped, not run)" do
    lines = { 3 => ["t1"] } # line 4 ran no test
    sparse = Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => lines }, tests: ["t1"])
    allow(self).to receive(:map).and_return(sparse)
    first = run_with(cache)
    expect(first.map(&:reason)).to include("no coverage")
    runs = first.count { |result| !result.reason } + 1
    run_with(cache)
    expect(runner).to have_received(:run).exactly(runs).times
  end

  it "runs only the mutants whose verdicts cannot be reused" do
    store = cache
    first = run_with(store)
    first_runs = first.size + 1
    # Forget one verdict: only it (and the neutral check) may run again.
    entries = JSON.parse(File.read(File.join(@root, "results.json")))
    entries["entries"].delete(entries["entries"].keys.first)
    File.write(File.join(@root, "results.json"), JSON.generate(entries))
    run_with(cache)
    expect(runner).to have_received(:run).exactly(first_runs + 2).times
  end

  it "runs everything without a cache" do
    run_with(nil)
    run_with(nil)
    expect(runner).to have_received(:run).at_least(4).times
  end
end
