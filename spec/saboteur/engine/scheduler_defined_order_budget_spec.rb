# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# The defined-order retry (#557) runs the mutant again, so it spends
# --max-duration like every other run the scheduler forks: never more than
# the time left, and nothing at all once the budget is spent.
RSpec.describe Saboteur::Engine::Scheduler, "defined-order retry and --max-duration (#557)" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:subject_under_test) { subjects_in("class BudgetTarget\n  def m(a)\n    a + 1\n  end\nend\n").first }
  let(:setup_example) { "./spec/budget_spec.rb[1:1]" }
  let(:asserting_example) { "./spec/budget_spec.rb[1:2]" }
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => [asserting_example] } },
                                         tests: [setup_example, asserting_example],
                                         durations: { setup_example => 100.0, asserting_example => 100.0 })
  end
  let(:candidates) { Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics) }
  let(:runner) { instance_double(Saboteur::Execution::Runner) }
  let(:prefix) { [setup_example, asserting_example] }
  let(:mutant_runs) { [] }
  let(:clock) { { now: 0.0 } }

  def outcome(status, failed_ids: [])
    Saboteur::Execution::Runner::Outcome.new(status: status, runtime: 0.1, failed_ids: failed_ids)
  end

  # The covering example alone fails (killed, then fails unchanged); the
  # prefix passes unchanged. after_unchanged moves the clock once the
  # unchanged prefix run is done.
  def fake_runner(after_unchanged:)
    allow(runner).to receive(:run) do |test_ids:, timeout:, mutation: nil, **|
      if test_ids == prefix && mutation
        mutant_runs << timeout
        outcome(:survived)
      elsif test_ids == prefix
        clock[:now] = after_unchanged
        outcome(:survived)
      else
        outcome(:killed, failed_ids: [asserting_example])
      end
    end
  end

  def results(deadline)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock[:now] }
    sched = described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                                reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics,
                                deadline: deadline)
    allow(sched).to receive(:load_problem).and_return(nil)
    sched.call(subject_under_test, candidates.for(subject_under_test))
  end

  it "forks no mutant retry once the unchanged prefix run has spent the budget" do
    fake_runner(after_unchanged: 100.0)
    final = results(100.0)
    expect([mutant_runs, final.map(&:status).uniq]).to eq([[], [:unverified]])
  end

  it "gives the mutant retry only the time the budget has left" do
    fake_runner(after_unchanged: 95.0)
    results(100.0)
    expect(mutant_runs).to all(be <= 5.0)
  end

  it "keeps the usual timeout when no --max-duration is set" do
    fake_runner(after_unchanged: 0.0)
    results(nil)
    expect(mutant_runs).to all(be > 5.0)
  end

  # A retry that the budget cut short and that times out proves nothing:
  # it is unverified, like every other budget-cut check (#296), never a
  # timeout verdict and never a kill.
  it "marks the mutant retry unverified, not timed out, when the budget capped it" do
    allow(runner).to receive(:run) do |test_ids:, mutation: nil, **|
      if test_ids == prefix && mutation
        outcome(:timeout)
      elsif test_ids == prefix
        clock[:now] = 95.0
        outcome(:survived)
      elsif mutation
        outcome(:killed, failed_ids: [asserting_example])
      else
        outcome(:killed)
      end
    end
    final = results(100.0)
    expect(final.map { |result| [result.status, result.reason] }.uniq)
      .to eq([[:unverified, described_class::BUDGET_RETRY_REASON]])
  end

  it "lets the mutant retry's timeout stand when the budget left it the full time" do
    allow(runner).to receive(:run) do |test_ids:, mutation: nil, **|
      if test_ids == prefix && mutation
        outcome(:timeout)
      elsif test_ids == prefix
        clock[:now] = 0.0
        outcome(:survived)
      elsif mutation
        outcome(:killed, failed_ids: [asserting_example])
      else
        outcome(:killed)
      end
    end
    final = results(1000.0)
    expect(final.map(&:status).uniq).to eq([:timeout])
  end

  it "lets the mutant retry's kill stand when the budget capped only its timeout" do
    allow(runner).to receive(:run) do |test_ids:, mutation: nil, **|
      if mutation
        outcome(:killed, failed_ids: [asserting_example])
      elsif test_ids == prefix
        clock[:now] = 95.0
        outcome(:survived)
      else
        outcome(:killed)
      end
    end
    final = results(100.0)
    expect(final.map { |result| [result.status, result.killed_by] }.uniq)
      .to eq([[:killed, [asserting_example]]])
  end
end
