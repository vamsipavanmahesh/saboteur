# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# --flaky-check (#476): a flaky test can make a mutant verdict
# untrustworthy. Bounded confirmation: at most one reordered rerun per
# decisive verdict; a disagreement is :unverified - outside the score,
# never cached, never retried until it passes.
RSpec.describe Saboteur::Engine::Scheduler, "flaky check (#476)" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:subject_under_test) { subjects_in("class FlakyTarget\n  def m(a)\n    a + 1\n  end\nend\n").first }
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => { 3 => %w[t1 t2] } },
                                         tests: %w[t1 t2], durations: { "t1" => 0.1, "t2" => 0.1 })
  end
  let(:candidates) { Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics) }
  let(:runner) { instance_double(Saboteur::Execution::Runner) }
  let(:mode) { "off" }

  def outcome(status, failed_ids: [], runtime: 1.0, message: nil)
    Saboteur::Execution::Runner::Outcome.new(status: status, runtime: runtime, failed_ids: failed_ids, message: message)
  end

  # outcomes: the outcomes each mutant run returns, in call order.
  def schedule(outcomes, mode:)
    calls = []
    allow(runner).to receive(:run) do |test_ids:, mutation: nil, **|
      calls << test_ids if mutation
      mutation ? outcomes.fetch((calls.size - 1) % outcomes.size) : outcome(:survived)
    end
    scheduler(mode).call(subject_under_test, candidates.for(subject_under_test))
    calls
  end

  def scheduler(mode)
    described_class.new(config: Saboteur::Config.new({ "flaky_check" => mode }),
                        runner: runner, map: map,
                        reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics).tap do |s|
      allow(s).to receive(:load_problem).and_return(nil)
    end
  end

  it "is off by default: a survivor gets no confirmation run" do
    mutants = candidates.for(subject_under_test)
    calls = schedule(Array.new(mutants.size) { outcome(:survived) }, mode: "off")
    expect(calls.size).to eq(mutants.size)
  end

  it "survivors mode reruns a survivor's tests once, in a different order" do
    mutants = candidates.for(subject_under_test)
    calls = schedule(Array.new(mutants.size) { outcome(:survived) }, mode: "survivors")
    expect(calls.size).to eq(mutants.size * 2)
    calls.each_slice(2) do |first, second|
      expect(second).to match_array(first)
      expect(second).not_to eq(first)
    end
  end

  it "keeps a survivor the confirmation run agrees with" do
    results = scheduler("survivors").tap {
      allow(runner).to receive(:run).and_return(outcome(:survived))
    }.call(subject_under_test, candidates.for(subject_under_test))
    expect(results.map(&:status).uniq).to eq([:survived])
  end

  it "makes a disagreed survivor unverified, naming the verdicts, and never caches it" do
    store = instance_double(Saboteur::Engine::ResultCache, record: nil, lookup: nil)
    sched = described_class.new(config: Saboteur::Config.new({ "flaky_check" => "survivors" }),
                                runner: runner, map: map,
                                reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics,
                                cache: store).tap { |s| allow(s).to receive(:load_problem).and_return(nil) }
    answers = [outcome(:survived), outcome(:killed, failed_ids: ["t2"])] * 10
    runs = 0
    allow(runner).to receive(:run) do |mutation: nil, **|
      mutation ? answers.fetch(runs.tap { runs += 1 }) : outcome(:survived)
    end
    results = sched.call(subject_under_test, candidates.for(subject_under_test))
    expect(results.map(&:status).uniq).to eq([:unverified])
    expect(results.first.reason).to include("survived").and include("killed").and include("t2")
    expect(store).not_to have_received(:record)
  end

  it "does not recheck kills in survivors mode" do
    mutants = candidates.for(subject_under_test)
    calls = schedule(Array.new(mutants.size) { outcome(:killed, failed_ids: ["t1"]) }, mode: "survivors")
    expect(calls.size).to eq(mutants.size)
  end

  it "decisive mode also rechecks a fresh kill" do
    mutants = candidates.for(subject_under_test)
    calls = schedule(Array.new(mutants.size) { outcome(:killed, failed_ids: ["t1"]) }, mode: "decisive")
    expect(calls.size).to eq(mutants.size * 2)
  end

  it "makes a disagreed kill unverified in decisive mode" do
    answers = [outcome(:killed, failed_ids: ["t1"]), outcome(:survived)] * 10
    runs = 0
    allow(runner).to receive(:run) do |mutation: nil, **|
      mutation ? answers.fetch(runs.tap { runs += 1 }) : outcome(:survived)
    end
    results = scheduler("decisive").call(subject_under_test, candidates.for(subject_under_test))
    expect(results.map(&:status).uniq).to eq([:unverified])
  end
end

RSpec.describe Saboteur::Config, "flaky_check (#476)" do
  it "defaults to off" do
    expect(described_class.new({})["flaky_check"]).to eq("off")
  end

  it "rejects an unknown mode" do
    expect { described_class.new({ "flaky_check" => "always" }) }
      .to raise_error(Saboteur::ConfigError, /flaky_check must be one of: off, survivors, decisive/)
  end
end

RSpec.describe Saboteur::Config, "flaky_check with test_command (#476)" do
  it "refuses the combination: external runs have no in-process scheduler to confirm through" do
    expect { described_class.new({ "test_command" => "bin/test", "flaky_check" => "survivors" }) }
      .to raise_error(Saboteur::ConfigError, /test_command cannot be combined with flaky_check/)
  end

  it "allows test_command with the check off" do
    expect(described_class.new({ "test_command" => "bin/test", "flaky_check" => "off" })["flaky_check"]).to eq("off")
  end
end

RSpec.describe Saboteur::CLI, "--flaky-check (#476)" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  it "parses the mode into the flaky_check config key" do
    command = described_class.new(["run", "--flaky-check", "decisive"], out: out, err: err)
    allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "stop")
    command.call
    expect(command.options[:flaky_check]).to eq("decisive")
  end

  it "rejects an unknown mode as a usage error" do
    command = described_class.new(["run", "--flaky-check", "always"], out: out, err: err)
    expect(command.call).to eq(2)
    expect(err.string).to include("flaky-check")
  end
end
