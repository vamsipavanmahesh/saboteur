# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# What the scheduler does when a mutant times out: the unchanged-method check,
# the verdicts and messages it gives, the slowdown it learns, the retry
# timeout, the budget cap and the sig prefix handed to the child.
RSpec.describe Saboteur::Engine::Scheduler, "timeout calibration" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:runner) { instance_double(Saboteur::Execution::Runner) }
  let(:subject_under_test) { subjects_in("class K\n  def m(a)\n    a + 1\n  end\nend\n").first }
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => %w[t1] } },
                                         tests: %w[t1], durations: { "t1" => 1.0 })
  end
  let(:mutation) do
    at = subject_under_test.file_source.index("+")
    edit = Saboteur::MutationSource::Edit.new(file: subject_under_test.file, start_byte: at, end_byte: at + 1,
                                              replacement: "-")
    Saboteur::MutationSource::Mutation.new(subject_id: subject_under_test.id, operator: "arithmetic", edits: [edit])
  end
  let(:text) { subject_under_test.apply(mutation.edits) }

  def outcome(status, runtime: 1.0, **rest)
    Saboteur::Execution::Runner::Outcome.new(status:, runtime:, failed_ids: [], **rest)
  end

  def scheduler(deadline: nil, wrapper: nil)
    s = described_class.new(config: Saboteur::Config.new({}), runner:, map:, diagnostics:, deadline:,
                            reevaluator: Saboteur::Execution::Reevaluator.new)
    allow(s).to receive(:load_problem).and_return([nil, wrapper])
    s
  end

  # Feeds the runner one outcome per call and records the keyword arguments.
  def feed(*outcomes)
    @calls = []
    queue = outcomes.dup
    allow(runner).to receive(:run) do |**args|
      @calls << args
      queue.shift || outcome(:survived)
    end
  end

  def result_of(sched)
    sched.call(subject_under_test, [[mutation, text]]).first
  end

  it "reports tests that fail with the method unchanged" do
    feed(outcome(:timeout), outcome(:killed))
    result = result_of(scheduler)
    expect([result.status, result.reason]).to eq([:error, "tests also fail with the method unchanged"])
  end

  it "reports tests that time out with the method unchanged and names baseline_timeout" do
    feed(outcome(:timeout), outcome(:timeout))
    result = result_of(scheduler)
    expect([result.status, result.reason]).to eq(
      [:error, "tests also time out with the method unchanged (raise baseline_timeout)"]
    )
  end

  it "keeps the timeout when the unchanged method is not slower, even at an equal deadline" do
    feed(outcome(:timeout), outcome(:survived, runtime: 0.5))
    expect(result_of(scheduler).status).to eq(:timeout)
    expect(@calls.size).to eq(2)
    equal = @calls.first[:timeout] / 3.0
    feed(outcome(:timeout), outcome(:survived, runtime: equal))
    expect(result_of(scheduler).status).to eq(:timeout)
    expect(@calls.size).to eq(2)
  end

  it "retries a slower unchanged run with its longer deadline and learns the slowdown" do
    feed(outcome(:timeout), outcome(:survived, runtime: 10.0), outcome(:killed))
    sched = scheduler
    expect(result_of(sched).status).to eq(:killed)
    first, unchanged, retry_call = @calls
    expect([first[:timeout], unchanged[:timeout]]).to eq([5.0, 300.0])
    expect(unchanged).not_to have_key(:mutation)
    expect(retry_call[:timeout]).to eq(30.0)
    expect(retry_call[:mutation]).to eq(mutation)
  end

  it "gives later mutants of the subject the measured slowdown" do
    at = subject_under_test.file_source.index("1")
    edit = Saboteur::MutationSource::Edit.new(file: subject_under_test.file, start_byte: at, end_byte: at + 1,
                                              replacement: "2")
    other = Saboteur::MutationSource::Mutation.new(subject_id: subject_under_test.id, operator: "literal_number",
                                                   edits: [edit])
    feed(outcome(:timeout), outcome(:survived, runtime: 10.0), outcome(:killed), outcome(:survived))
    scheduler.call(subject_under_test, [[mutation, text], [other, subject_under_test.apply(other.edits)]])
    expect(@calls.first(4).map { |call| call[:timeout] }).to eq([5.0, 300.0, 30.0, 30.0])
  end

  it "keeps a retry that times out again as a timeout" do
    feed(outcome(:timeout), outcome(:survived, runtime: 10.0), outcome(:timeout, runtime: 30.0))
    expect(result_of(scheduler).status).to eq(:timeout)
    feed(outcome(:timeout), outcome(:survived, runtime: 10.0), outcome(:survived, runtime: 2.0))
    expect(result_of(scheduler).status).to eq(:survived)
  end

  it "passes the full baseline timeout to the unchanged run when the budget has plenty left" do
    feed(outcome(:timeout), outcome(:timeout))
    result_of(scheduler(deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10_000))
    expect(@calls[1][:timeout]).to eq(300.0)
  end

  it "makes a timeout unverified when the budget cut the unchanged run short" do
    feed(outcome(:timeout), outcome(:timeout, runtime: 4.0))
    result = result_of(scheduler(deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 50))
    expect([result.status, result.reason]).to eq(
      [:unverified, "the --max-duration budget cut the timeout calibration short"]
    )
    expect(@calls[1][:timeout]).to be <= 50.0
  end

  it "hands the sorbet sig to the child only for a sorbet wrapper" do
    allow(subject_under_test).to receive(:sig_source).and_return("sig { void }")
    feed(outcome(:survived))
    result_of(scheduler(wrapper: :sorbet))
    expect(@calls.first[:eval_prefix]).to eq("sig { void }")
    feed(outcome(:survived))
    result_of(scheduler(wrapper: :other))
    expect(@calls.first[:eval_prefix]).to be_nil
  end

  it "never lets the budget cap go below zero" do
    sched = scheduler(deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) - 5)
    expect(sched.send(:budget_capped, 12.0)).to eq(0.0)
    expect(scheduler.send(:budget_capped, 12.0)).to eq(12.0)
  end

  it "keeps the timeout when the unchanged deadline is shorter than the mutant's" do
    slow = Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => %w[t1] } },
                                                tests: %w[t1], durations: { "t1" => 3.0 })
    allow(self).to receive(:map).and_return(slow)
    feed(outcome(:timeout), outcome(:survived, runtime: 0.5))
    expect(result_of(scheduler).status).to eq(:timeout)
    expect(@calls.size).to eq(2)
  end

  it "learns no slowdown, and does not fail, when the recorded runtime is missing or zero" do
    [{}, { "t1" => 0.0 }].each do |durations|
      bare = Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => %w[t1] } },
                                                  tests: %w[t1], durations:)
      allow(self).to receive(:map).and_return(bare)
      feed(outcome(:timeout), outcome(:survived, runtime: 1000.0), outcome(:killed))
      expect(result_of(scheduler).status).to eq(:killed)
      expect(@calls[2][:timeout]).to eq(3000.0)
    end
  end

  it "marks a retry the budget cut short as unverified, but keeps a verdict it still reached" do
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    feed(outcome(:timeout), outcome(:survived, runtime: 10.0), outcome(:timeout, runtime: 20.0))
    result = result_of(scheduler(deadline: now + 25))
    expect([result.status, result.reason]).to eq([:unverified, "the --max-duration budget cut the mutant retry short"])
    expect(@calls.last[:timeout]).to be < 30.0
    feed(outcome(:timeout), outcome(:survived, runtime: 10.0), outcome(:killed))
    expect(result_of(scheduler(deadline: now + 25)).status).to eq(:killed)
  end

  it "keeps the largest slowdown it has measured" do
    others = %w[2 3].map do |digit|
      at = subject_under_test.file_source.index("1")
      edit = Saboteur::MutationSource::Edit.new(file: subject_under_test.file, start_byte: at, end_byte: at + 1,
                                                replacement: digit)
      Saboteur::MutationSource::Mutation.new(subject_id: subject_under_test.id, operator: "literal_number",
                                             edits: [edit])
    end
    feed(outcome(:timeout), outcome(:survived, runtime: 10.0), outcome(:killed),
         outcome(:timeout), outcome(:survived, runtime: 4.0), outcome(:survived))
    candidates = [[mutation, text]] + others.map { |m| [m, subject_under_test.apply(m.edits)] }
    scheduler.call(subject_under_test, candidates)
    expect(@calls[5][:timeout]).to eq(30.0)
  end
end
