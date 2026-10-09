# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# The scheduler's whole flow against a fake runner that records every call
# and answers with outcomes chosen per mutant operator.
RSpec.describe Saboteur::Engine::Scheduler, "flow" do
  let(:err) { StringIO.new }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(err) }
  let(:subject_under_test) do
    subjects_in("class FlowTarget\n  def m(a)\n    b = a + 1\n    b * 2\n  end\nend\n", name: "flow_target.rb").first
  end
  # t_all runs every line; t_three only line 3; t_four only line 4.
  let(:lines) { { 3 => %w[t_all t_three], 4 => %w[t_all t_four] } }
  let(:map) do
    Saboteur::Selection::CoverageMap.new(lines: { subject_under_test.file => lines }, tests: %w[t_all t_three t_four])
  end
  let(:calls) { [] }
  let(:answers) { {} }

  # The outcome of every run of the unchanged method; an example sets
  # @neutral to change it.
  def neutral
    @neutral || outcome(:survived, runtime: 2.0)
  end

  def outcome(status, runtime: 0.1, **rest)
    Saboteur::Execution::Runner::Outcome.new(status:, runtime:, **rest)
  end

  def runner
    recorded = calls
    replies = answers
    first = neutral
    double("runner").tap do |fake|
      allow(fake).to receive(:run) do |**args|
        recorded << args
        next first if args[:mutation].nil?

        replies.fetch(args[:mutation].operator) { outcome(:killed, failed_ids: [args[:test_ids].first]) }
      end
    end
  end

  def scheduler(config: {}, load_problem: nil)
    described_class.new(config: Saboteur::Config.new(config), runner: runner, map: map,
                        reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics).tap do |s|
      allow(s).to receive(:load_problem).and_return(load_problem) unless load_problem == :real
    end
  end

  def candidates
    Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics).for(subject_under_test)
  end

  def mutant_calls
    calls.reject { |call| call[:mutation].nil? }
  end

  it "does nothing without candidates" do
    expect(scheduler.call(subject_under_test, [])).to eq([])
    expect(calls).to be_empty
  end

  it "skips everything, without running, for a subject that cannot be run" do
    results = scheduler(load_problem: "method not loaded").call(subject_under_test, candidates)
    expect(results.map(&:reason).uniq).to eq(["method not loaded"])
    expect(calls).to be_empty
  end

  it "uses the subject's own skip reason first" do
    subject_under_test.skip_reason = "refinements"
    expect(scheduler.call(subject_under_test, candidates).map(&:reason).uniq).to eq(["refinements"])
  end

  it "finds a method that is not loaded with the real check" do
    results = scheduler(load_problem: :real).call(subject_under_test, candidates)
    expect(results.map(&:reason).uniq)
      .to eq(["owner not loaded: cannot resolve FlowTarget: uninitialized constant FlowTarget"])
  end

  it "skips everything as no coverage when no test runs the method" do
    lines.clear
    expect(scheduler.call(subject_under_test, candidates).map(&:reason).uniq).to eq(["no coverage"])
    expect(calls).to be_empty
  end

  it "runs the mutants first, then the unchanged method with only the tests that killed" do
    scheduler.call(subject_under_test, candidates)
    expect(calls.first[:mutation]).not_to be_nil
    expect(calls.last.values_at(:text, :mutation)).to eq([subject_under_test.source, nil])
    expect(calls.count { |call| call[:mutation].nil? }).to eq(1)
    expect(calls.last[:test_ids]).to eq(mutant_calls.flat_map { |call| call[:test_ids].first(1) }.uniq)
  end

  it "warns once per subject about verdicts that failed with the method unchanged" do
    @neutral = outcome(:killed, failed_ids: %w[t_all t_three t_four])
    results = scheduler.call(subject_under_test, candidates)
    expect(results.map(&:status).uniq).to eq([:error])
    expect(diagnostics.warnings).to eq(["FlowTarget#m: #{results.size} verdict(s) failed with the method unchanged"])
  end

  it "warns about processes a child left running" do
    @neutral = outcome(:survived, runtime: 1.0, leftover_pids: [11, 12])
    answers["body_nil"] = outcome(:killed, failed_ids: ["t_all"], leftover_pids: [13])
    scheduler.call(subject_under_test, candidates)
    expect(diagnostics.warnings).to include("FlowTarget#m verdict check: killed 2 process(es) it left running")
    expect(diagnostics.warnings.grep(/body_nil \h{16}: killed 1 process/).size).to eq(1)
  end

  it "prints one progress mark per executed mutant" do
    results = scheduler.call(subject_under_test, candidates)
    expect(err.string.length).to eq(results.size)
  end

  it "gives coarse mutants every test of the method and fine mutants only those that ran their line" do
    scheduler.call(subject_under_test, candidates)
    by_operator = mutant_calls.group_by { |call| call[:mutation].operator }
    expect(by_operator["body_nil"].first[:test_ids]).to match_array(%w[t_all t_three t_four])
    line_four = mutant_calls.find { |call| call[:mutation].operator == "arithmetic" && call[:text].include?("b / 2") }
    expect(line_four[:test_ids]).to match_array(%w[t_all t_four])
  end

  it "skips a fine mutant whose line no test ran, without running it" do
    lines.delete(4)
    lines[3] = %w[t_all]
    results = scheduler.call(subject_under_test, candidates)
    line_four = results.find { |result| result.mutated_source.include?("b / 2") }
    expect(line_four.reason).to eq("no coverage")
  end

  it "runs the tests that killed earlier mutants first" do
    answers["body_nil"] = outcome(:killed, failed_ids: ["t_four"])
    scheduler.call(subject_under_test, candidates)
    body_raise = mutant_calls.find { |call| call[:mutation].operator == "body_raise" }
    expect(body_raise[:test_ids].first).to eq("t_four")
    expect(described_class.prioritize(%w[a b], { "b" => 2, "a" => 1 })).to eq(%w[b a])
  end
end
