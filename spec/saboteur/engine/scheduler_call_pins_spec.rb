# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Pins for the scheduler's entry guards and the verdicts it reuses from the
# result cache: the order tests run in, the empty and sorbet guards, the
# all-reusable shortcut and every field a reused result carries.
RSpec.describe Saboteur::Engine::Scheduler, "call guards and reuse" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:runner) { instance_double(Saboteur::Execution::Runner) }
  let(:cache) { instance_double(Saboteur::Engine::ResultCache) }
  let(:subject_under_test) { subjects_in("class K\n  def m(a)\n    a + 1\n  end\nend\n").first }
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => %w[t1 t2] } },
                                         tests: %w[t1 t2], durations: { "t1" => 0.1, "t2" => 0.1 })
  end
  let(:mutation) do
    at = subject_under_test.file_source.index("+")
    edit = Saboteur::MutationSource::Edit.new(file: subject_under_test.file, start_byte: at, end_byte: at + 1,
                                              replacement: "-")
    Saboteur::MutationSource::Mutation.new(subject_id: subject_under_test.id, operator: "arithmetic", edits: [edit])
  end
  let(:text) { subject_under_test.apply(mutation.edits) }

  def scheduler(store: nil, deadline: nil)
    described_class.new(config: Saboteur::Config.new({}), runner:, map:, diagnostics:, cache: store, deadline:,
                        reevaluator: Saboteur::Execution::Reevaluator.new)
  end

  def hit(**fields)
    { status: :killed, reason: "why", runtime: 0.25, killed_by: %w[t2], kill_cause: "assertion" }.merge(fields)
  end

  it "runs the tests that killed the most earlier mutants first, then keeps the given order" do
    expect(described_class.prioritize(%w[a b c d], { "c" => 2, "b" => 1 })).to eq(%w[c b a d])
    ties = (1..60).map { |n| "t#{n}" }
    expect(described_class.prioritize(ties, {})).to eq(ties)
    expect(described_class.prioritize(ties, Hash.new(0).merge("t60" => 1))).to eq(["t60"] + ties.first(59))
  end

  it "returns nothing for no candidates without asking the map or the runner" do
    allow(map).to receive(:tests_for)
    expect(runner).not_to receive(:run)
    s = scheduler
    allow(s).to receive(:load_problem).and_return([nil, nil])
    expect(s.call(subject_under_test, [])).to eq([])
    expect(map).not_to have_received(:tests_for)
  end

  it "skips a sorbet-wrapped def whose sig is not found, naming the reason" do
    s = scheduler
    allow(s).to receive(:load_problem).and_return([nil, :sorbet])
    allow(subject_under_test).to receive(:sig_source).and_return(nil)
    expect(runner).not_to receive(:run)
    result = s.call(subject_under_test, [[mutation, text]]).first
    expect([result.status, result.reason]).to eq(
      [:skipped, "sorbet sig not found next to the def; cannot preserve runtime type checks"]
    )
  end

  it "does not skip a sorbet-wrapped def when its sig is found, or a plain def without one" do
    allow(runner).to receive(:run).and_return(
      Saboteur::Execution::Runner::Outcome.new(status: :survived, runtime: 0.1, failed_ids: [])
    )
    s = scheduler
    allow(s).to receive(:load_problem).and_return([nil, :sorbet])
    allow(subject_under_test).to receive(:sig_source).and_return("sig { void }")
    expect(s.call(subject_under_test, [[mutation, text]]).map(&:status)).to eq([:survived])
    plain = scheduler
    allow(plain).to receive(:load_problem).and_return([nil, :other])
    allow(subject_under_test).to receive(:sig_source).and_return(nil)
    expect(plain.call(subject_under_test, [[mutation, text]]).map(&:status)).to eq([:survived])
  end

  it "carries every cached field onto a reused result and forks nothing when all are reusable" do
    allow(cache).to receive(:lookup).and_return(hit)
    expect(runner).not_to receive(:run)
    expect(cache).to receive(:lookup).once.and_return(hit)
    s = scheduler(store: cache)
    allow(s).to receive(:load_problem).and_return(nil)
    result = s.call(subject_under_test, [[mutation, text]]).first
    expect([result.status, result.reason, result.runtime, result.killed_by, result.kill_cause]).to eq(
      [:killed, "why", 0.25, %w[t2], "assertion"]
    )
    expect([result.covered_by, result.reused?, result.mutated_source]).to eq([%w[t1 t2], true, text])
  end

  it "runs a mutant the cache has no verdict for" do
    allow(cache).to receive(:lookup).and_return(nil)
    allow(cache).to receive(:record)
    allow(runner).to receive(:run).and_return(
      Saboteur::Execution::Runner::Outcome.new(status: :survived, runtime: 0.1, failed_ids: [])
    )
    s = scheduler(store: cache)
    allow(s).to receive(:load_problem).and_return(nil)
    results = s.call(subject_under_test, [[mutation, text]])
    expect(results.map(&:reused?)).to eq([false])
    expect(runner).to have_received(:run).at_least(:once)
  end

  it "stops between mutants once the deadline has passed" do
    allow(runner).to receive(:run)
    s = scheduler(deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
    allow(s).to receive(:load_problem).and_return(nil)
    expect(s.call(subject_under_test, [[mutation, text]])).to eq([])
  end

  it "does not consult the cache for a mutation on a line no test ran" do
    sub = subjects_in("class K\n  def m(a)\n    b = a\n    b + 1\n  end\nend\n").first
    sparse = Saboteur::Selection::CoverageMap.new(lines: { sub.file => { 4 => %w[t1] } }, tests: %w[t1],
                                                  durations: { "t1" => 0.1 })
    at = sub.file_source.index("= a") + 2
    edit = Saboteur::MutationSource::Edit.new(file: sub.file, start_byte: at, end_byte: at + 1, replacement: "nil")
    uncovered = Saboteur::MutationSource::Mutation.new(subject_id: sub.id, operator: "test", edits: [edit])
    expect(cache).not_to receive(:lookup)
    expect(runner).not_to receive(:run)
    s = described_class.new(config: Saboteur::Config.new({}), runner:, map: sparse, diagnostics:, cache:,
                            reevaluator: Saboteur::Execution::Reevaluator.new)
    allow(s).to receive(:load_problem).and_return([nil, nil])
    result = s.call(sub, [[uncovered, sub.apply(uncovered.edits)]]).first
    expect([result.reused?, result.covered_by]).to eq([false, []])
    expect(result.status).not_to eq(:survived)
  end
end
