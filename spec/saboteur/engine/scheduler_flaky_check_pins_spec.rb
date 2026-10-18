# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Pins for the --flaky-check confirmation run (#476): what the rerun is
# called with, how the tests are reordered, and what the disagreement
# verdict reports. The scheduler_flaky_check_spec stubs the runner without
# looking at the call, so these read the call itself.
RSpec.describe Saboteur::Engine::Scheduler, "flaky check pins (#476)" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:subject_under_test) { subjects_in("class FlakyPins\n  def m(a)\n    a + 1\n  end\nend\n").first }
  let(:tests) { %w[t1 t2 t3 t4] }
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => tests } },
                                         tests: tests, durations: tests.to_h { |t| [t, 0.1] })
  end
  let(:runner) { instance_double(Saboteur::Execution::Runner) }
  let(:plan) { Struct.new(:subject, :slowdown, :wrapper).new(subject_under_test, 100.0, nil) }
  let(:mutation) { Object.new }

  def outcome(status, failed_ids: [], runtime: 1.0)
    Saboteur::Execution::Runner::Outcome.new(status: status, runtime: runtime, failed_ids: failed_ids)
  end

  def scheduler(mode, seed: 1, deadline: nil)
    described_class.new(config: Saboteur::Config.new({ "flaky_check" => mode, "seed" => seed }),
                        runner: runner, map: map, reevaluator: Saboteur::Execution::Reevaluator.new,
                        diagnostics: diagnostics, deadline: deadline)
  end

  def check(sched, first, order: tests)
    sched.send(:flaky_check, plan, mutation, "mutated text", order, first)
  end

  describe "rerun call" do
    it "passes the subject, text, mutation, eval prefix and slowdown-scaled timeout through" do
      sched = scheduler("survivors")
      allow(sched).to receive(:eval_prefix).with(plan).and_return("sig prefix")
      allow(runner).to receive(:run).and_return(outcome(:survived))
      expect(sched.timeout_for(tests, 100.0)).not_to eq(sched.timeout_for(tests, 1.0))
      check(sched, outcome(:survived))
      expect(runner).to have_received(:run)
        .with(subject: subject_under_test, text: "mutated text", test_ids: a_collection_containing_exactly(*tests),
              timeout: sched.timeout_for(tests, 100.0), mutation: mutation, eval_prefix: "sig prefix").once
    end
  end

  describe "budget" do
    it "makes no confirmation run once the budget is spent" do
      allow(runner).to receive(:run)
      first = outcome(:survived)
      expect(check(scheduler("survivors", deadline: 0.0), first)).to equal(first)
      expect(runner).not_to have_received(:run)
    end
  end

  describe "calibration before the check" do
    it "calibrates a timed-out mutant instead of reporting the raw timeout" do
      sched = scheduler("off")
      allow(runner).to receive(:run).and_return(outcome(:timeout, runtime: 3.0))
      result = sched.send(:run_mutant, plan, mutation, "mutated text", tests)
      expect(result.status).to eq(:error)
      expect(result.message).to include("tests also time out with the method unchanged")
    end
  end

  describe "which verdicts are checked" do
    it "rechecks a survivor in decisive mode" do
      allow(runner).to receive(:run).and_return(outcome(:survived))
      check(scheduler("decisive"), outcome(:survived))
      expect(runner).to have_received(:run).once
    end

    it "rechecks a kill in decisive mode" do
      allow(runner).to receive(:run).and_return(outcome(:killed))
      check(scheduler("decisive"), outcome(:killed))
      expect(runner).to have_received(:run).once
    end

    it "does not recheck a timeout, error or unverified verdict" do
      allow(runner).to receive(:run)
      %i[timeout error unverified].each { |status| check(scheduler("decisive"), outcome(status)) }
      expect(runner).not_to have_received(:run)
    end
  end

  describe "disagreement verdict" do
    it "is unverified, adds both runtimes, and names the verdicts and decisive tests" do
      allow(runner).to receive(:run).and_return(outcome(:survived, runtime: 2.25))
      result = check(scheduler("decisive"), outcome(:killed, failed_ids: ["t1"], runtime: 1.5))
      expect(result.status).to eq(:unverified)
      expect(result.runtime).to eq(3.75)
      expect(result.message).to eq("flaky verdict: first killed, then survived on a reordered confirmation " \
                                   "run (decisive tests: t1) - the mutant is unverified, not killed")
    end

    it "names at most three decisive tests, each once, in first-then-rerun order" do
      allow(runner).to receive(:run).and_return(outcome(:killed, failed_ids: %w[t2 t3 t4]))
      result = check(scheduler("decisive"), outcome(:survived, failed_ids: %w[t1 t2]))
      expect(result.message).to include("(decisive tests: t1, t2, t3)")
    end

    it "omits the decisive tests clause when none failed" do
      allow(runner).to receive(:run).and_return(outcome(:killed))
      result = check(scheduler("survivors"), outcome(:survived))
      expect(result.message).to eq("flaky verdict: first survived, then killed on a reordered confirmation " \
                                   "run - the mutant is unverified, not survived")
    end

    it "returns the first outcome itself when the rerun agrees" do
      allow(runner).to receive(:run).and_return(outcome(:survived, runtime: 9.0))
      first = outcome(:survived)
      expect(check(scheduler("survivors"), first)).to equal(first)
    end
  end

  describe "reordering" do
    def reordered(tests, seed)
      scheduler("survivors", seed: seed).send(:reordered, tests)
    end

    def seed_where(list, same:)
      (0..500).find { |seed| (list.shuffle(random: Random.new(seed)) == list) == same }
    end

    it "keeps a shuffle that already differs as the shuffle, not a rotation of it" do
      seed = (0..500).find do |s|
        shuffled = tests.shuffle(random: Random.new(s))
        shuffled != tests && shuffled != tests.rotate
      end
      expect(reordered(tests, seed)).to eq(tests.shuffle(random: Random.new(seed)))
    end

    it "rotates a shuffle that came out identical, so the order always differs" do
      seed = seed_where(%w[a b], same: true)
      expect(reordered(%w[a b], seed)).to eq(%w[b a])
    end

    it "rotates a longer identical shuffle by one" do
      seed = seed_where(%w[a b c], same: true)
      expect(reordered(%w[a b c], seed)).to eq(%w[b c a])
    end

    it "leaves a single test alone" do
      expect(reordered(%w[a], 1)).to eq(%w[a])
    end

    it "is deterministic for a seed" do
      expect(reordered(tests, 7)).to eq(reordered(tests, 7))
    end
  end
end
