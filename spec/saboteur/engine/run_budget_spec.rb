# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine, "RunBudget and mutate flow pins (#443 dogfood)" do
  def engine_with(config_values)
    described_class.new(Saboteur::Config.new(config_values, root: Dir.mktmpdir), err: StringIO.new)
  end

  def store_with(reusable)
    Object.new.tap { |store| store.define_singleton_method(:reusable?) { |_files| reusable } }
  end

  describe "#refuse_unaffordable_coverage_build" do
    # One row per early return and the raise: with the clock frozen at
    # 1000.0 and the run started 40.0s ago, a 60s budget leaves 20.0s;
    # 47.3s over 2 passes is 23.65s per pass, so the build is refused
    # unless a guard says otherwise.
    {
      "no max_duration configured" => [{}, false, 47.3, 2, 40.0],
      "a reusable coverage cache" => [{ "max_duration" => 60 }, true, 47.3, 2, 40.0],
      "zero completed baseline passes" => [{ "max_duration" => 60 }, false, 47.3, 0, 40.0],
      "a spent budget (remaining <= 0)" => [{ "max_duration" => 60 }, false, 47.3, 2, 70.0],
      "an untimed (zero-second) baseline" => [{ "max_duration" => 60 }, false, 0.0, 2, 40.0],
      "a budget that covers one more pass" => [{ "max_duration" => 60 }, false, 47.3, 2, 10.0],
      "a budget at exactly one more pass" => [{ "max_duration" => 60 }, false, 20.0, 2, 50.0],
      # remaining == 0.0 exactly: the spent-budget guard returns before the
      # affordability check, it does not refuse (kills <= -> <).
      "a budget spent to the second (remaining == 0.0)" => [{ "max_duration" => 60 }, false, 47.3, 2, 60.0]
    }.each do |name, (config, reusable, elapsed, passes, started_ago)|
      it "admits the build: #{name}" do
        engine = engine_with(config)
        now = 1000.0
        engine.instance_variable_set(:@run_started, now - started_ago)
        allow(Process).to receive(:clock_gettime).and_return(now)
        expect do
          engine.send(:refuse_unaffordable_coverage_build, store_with(reusable), [], elapsed, passes)
        end.not_to raise_error
      end
    end

    # remaining in (0, 1]: a sub-second remainder is not a spent budget
    # (kills remaining <= 0 -> <= 1).
    it "refuses when a fractional remainder cannot cover the pass" do
      engine = engine_with({ "max_duration" => 60 })
      engine.instance_variable_set(:@run_started, 940.5)
      allow(Process).to receive(:clock_gettime).and_return(1000.0)
      expect { engine.send(:refuse_unaffordable_coverage_build, store_with(false), [], 4.0, 2) }
        .to raise_error(Saboteur::BudgetPhaseTimeout)
    end

    # per_pass in (0, 1]: a fast pass still prices the build
    # (kills per_pass <= 0 -> <= 1).
    it "refuses when the pass is fast but the remainder is faster" do
      engine = engine_with({ "max_duration" => 60 })
      engine.instance_variable_set(:@run_started, 940.25)
      allow(Process).to receive(:clock_gettime).and_return(1000.0)
      expect { engine.send(:refuse_unaffordable_coverage_build, store_with(false), [], 1.0, 2) }
        .to raise_error(Saboteur::BudgetPhaseTimeout)
    end

    it "refuses with the full shortfall message, every interpolation pinned" do
      engine = engine_with({ "max_duration" => 60 })
      engine.instance_variable_set(:@run_started, 960.0)
      allow(Process).to receive(:clock_gettime).and_return(1000.0)
      expect { engine.send(:refuse_unaffordable_coverage_build, store_with(false), [], 47.3, 2) }
        .to raise_error(Saboteur::BudgetPhaseTimeout,
                        eq("the --max-duration budget cannot cover the coverage map build: baseline passes " \
                           "took about 24s each, only 20.0s remain, and a cold build needs about one more " \
                           "full pass and keeps nothing when it is cut off. Re-run with --max-duration about " \
                           "4s higher, fewer --baseline-passes, or once without --max-duration so the " \
                           "coverage cache is built for later --incremental runs"))
    end
  end

  describe "#refuse_unaffordable_coverage_build remainder rounding" do
    it "rounds a fractional remainder to one decimal place" do
      engine = engine_with({ "max_duration" => 60 })
      engine.instance_variable_set(:@run_started, 940.37)
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(1000.0)
      expect { engine.send(:refuse_unaffordable_coverage_build, store_with(false), [], 47.3, 2) }
        .to raise_error(Saboteur::BudgetPhaseTimeout, /only 0\.4s remain,/)
    end
  end

  describe "#check_baseline stability" do
    def guard_with(passes)
      instance_double(Saboteur::Engine::BaselineGuard, call: nil, completed_passes: passes)
    end

    it "is not a stable suite with exactly one completed pass" do
      allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(guard_with(1))
      engine = engine_with({})
      engine.send(:check_baseline, instance_double(Saboteur::Integration::RSpec), 1)
      expect(engine.instance_variable_get(:@stable_suite)).to eq(false)
      expect(engine.instance_variable_get(:@completed_baseline_passes)).to eq(1)
    end

    it "is a stable suite with more than two completed passes (>= 2, not == 2)" do
      allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(guard_with(3))
      engine = engine_with({})
      engine.send(:check_baseline, instance_double(Saboteur::Integration::RSpec), 3)
      expect(engine.instance_variable_get(:@stable_suite)).to eq(true)
      expect(engine.instance_variable_get(:@completed_baseline_passes)).to eq(3)
    end

    it "is a stable suite with two completed passes" do
      allow(Saboteur::Engine::BaselineGuard).to receive(:new).and_return(guard_with(2))
      engine = engine_with({})
      engine.send(:check_baseline, instance_double(Saboteur::Integration::RSpec), 2)
      expect(engine.instance_variable_get(:@stable_suite)).to eq(true)
    end
  end

  describe "#mutate flow" do
    def engine_for_mutate(config = {})
      engine = engine_with(config)
      store = store_with(true)
      allow(store).to receive(:fetch).and_return(:map)
      allow(engine).to receive(:coverage_store).and_return(store)
      stub_mutate_pipeline(engine, store)
      engine
    end

    # Everything between the coverage store and the candidate lists is
    # not under test here: each piece has its own pins. The refusal check
    # is an expectation, not a stub: dropping the call must fail (dogfood
    # e29ae47b39d8c901).
    def stub_mutate_pipeline(engine, store)
      allow(engine).to receive(:warn_unscoped)
      allow(engine).to receive(:check_baseline)
      expect(engine).to receive(:refuse_unaffordable_coverage_build).with(store, [])
      allow(engine).to receive(:abandon_for_budget?).and_return(false)
      allow(engine).to receive(:inform_about_run)
      allow(engine).to receive(:result_cache).and_return(nil)
      allow(engine).to receive(:scheduler_for).and_return(:scheduler)
    end

    it "returns no results when every subject's candidate list is empty" do
      engine = engine_for_mutate
      allow(engine).to receive(:candidate_lists).and_return([[], []])
      expect(engine).not_to receive(:run_candidates)
      expect(engine.send(:mutate, %i[a b], [], instance_double(Saboteur::Integration::RSpec), :scope, :ignore))
        .to eq([])
    end

    it "prepares the rails workers with the configured job count before forking" do
      engine = engine_for_mutate({ "jobs" => 3 })
      allow(engine).to receive(:candidate_lists).and_return([[:mutant]])
      rails = Object.new
      engine.instance_variable_set(:@rails, rails)
      expect(rails).to receive(:prepare_workers).with(3)
      # The runnable subjects and their candidate lists reach the run in
      # shape: rows, not the raw zipped pairs.
      expect(engine).to receive(:run_candidates).with([:a], [[:mutant]], anything, anything, anything)
                                                .and_return([])
      engine.send(:mutate, [:a], [], instance_double(Saboteur::Integration::RSpec), :scope, :ignore)
    end

    it "runs without rails to prepare" do
      engine = engine_for_mutate
      allow(engine).to receive(:candidate_lists).and_return([[:mutant]])
      allow(engine).to receive(:run_candidates).and_return([])
      expect do
        engine.send(:mutate, [:a], [], instance_double(Saboteur::Integration::RSpec), :scope, :ignore)
      end.not_to raise_error
    end
  end
end
