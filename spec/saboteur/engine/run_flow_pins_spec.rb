# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Pins Engine#mutate plumbing: the coverage files reach the result cache,
# a budget timeout in any phase becomes a budget stop, the budget check is
# part of the stop checks, and the runner gets the canary.
RSpec.describe Saboteur::Engine, "run flow pins" do
  let(:engine) { described_class.new(Saboteur::Config.new({}), err: StringIO.new) }
  let(:map) { instance_double(Saboteur::Selection::CoverageMap, tests: []) }
  let(:store) { instance_double(Saboteur::Engine::CoverageStore, reusable?: true, fetch: map) }

  before do
    allow(engine).to receive(:coverage_store).and_return(store)
    allow(engine).to receive(:warn_unscoped)
    allow(engine).to receive(:check_baseline)
    allow(engine).to receive(:refuse_unaffordable_coverage_build)
    allow(engine).to receive(:abandon_for_budget?).and_return(false)
    allow(engine).to receive(:scheduler_for).and_return(:scheduler)
    allow(Saboteur::Execution::ForkReadiness).to receive(:prepare_heap)
  end

  it "hands the coverage map and the test files to the result cache" do
    allow(engine).to receive(:candidate_lists).and_return([[]])
    expect(engine).to receive(:result_cache).with(map, ["spec/a_spec.rb"]).and_return(nil)
    expect(engine.send(:mutate, [:subject], ["spec/a_spec.rb"], :integration, nil, :ignore_list)).to eq([])
  end

  it "turns a budget timeout during execution into a budget stop" do
    allow(engine).to receive(:result_cache).and_return(nil)
    allow(engine).to receive(:candidate_lists).and_return([[:candidate]])
    error = Saboteur::BudgetPhaseTimeout.new("out of time")
    allow(engine).to receive(:run_candidates).and_raise(error)
    allow(engine).to receive(:budget_phase_stop).and_return(:stopped)
    expect(engine.send(:mutate, [:subject], ["spec/a_spec.rb"], :integration, nil, :ignore_list)).to eq(:stopped)
    expect(engine).to have_received(:budget_phase_stop).with(error, [:subject])
  end

  it "stops when the budget is exceeded, even without --fail-fast" do
    allow(engine).to receive(:budget_exceeded?).and_return(true)
    expect(engine.send(:stop_checks, :ignore_list).call([])).to be(true)
  end

  it "hands the canary and the sandbox hook to the runner" do
    allow(engine).to receive(:scheduler_for).and_call_original
    allow(engine).to receive(:canary).and_return(:canary_double)
    allow(engine).to receive(:sandbox_hook).and_return(:hook)
    allow(engine).to receive(:supervisor).and_return(:supervisor)
    allow(engine).to receive(:fresh_log_dir).and_return("logs")
    allow(engine).to receive(:budget_deadline).and_return(nil)
    runner = instance_double(Saboteur::Execution::Runner)
    expect(Saboteur::Execution::Runner).to receive(:new)
      .with(hash_including(canary: :canary_double, sandbox: :hook, hooks: engine.hooks))
      .and_return(runner)
    allow(Saboteur::Engine::Scheduler).to receive(:new)
    engine.send(:scheduler_for, map, :integration, :cache)
  end
end
