# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# The statuses mutants get when no test can judge them: code that only ran
# while the app loaded (ran at load), and defs a captured Method object
# still calls in their original form (unreachable); plus the sorbet sig
# wrapper, which must not read as a shadowed definition.
RSpec.describe Saboteur::Engine::Scheduler, "load-time statuses" do
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:runner) { instance_double(Saboteur::Execution::Runner) }

  def scheduler_for(map)
    described_class.new(config: Saboteur::Config.new({}), runner: runner, map: map,
                        reevaluator: Saboteur::Execution::Reevaluator.new, diagnostics: diagnostics)
  end

  def outcome(status, message: nil, failed_ids: [])
    Saboteur::Execution::Runner::Outcome.new(status: status, runtime: 0.5, message: message,
                                             failed_ids: failed_ids)
  end

  def edit_around(subject, needle, replacement: "x")
    at = subject.file_source.index(needle)
    Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + needle.length,
                                       replacement: replacement)
  end

  it "keeps the tests the child reported as run on the result" do
    subject = subjects_in("class ExecutedTarget\n  def m(a)\n    a + 1\n  end\nend\n").first
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => %w[t1 t2] } },
                                               tests: %w[t1 t2], durations: { "t1" => 0.1, "t2" => 0.1 })
    scheduler = scheduler_for(map)
    allow(scheduler).to receive(:load_problem).and_return([nil, nil])
    ran = Saboteur::Execution::Runner::Outcome.new(status: :killed, runtime: 0.5, failed_ids: %w[t1],
                                                   executed_ids: %w[t1], kill_cause: "assertion")
    allow(runner).to receive(:run).and_return(ran, outcome(:survived))
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison",
                                                      edits: [edit_around(subject, "+", replacement: "-")])
    result = scheduler.call(subject, [[mutation, subject.source]]).first
    expect([result.executed, result.complete?, result.kill_cause]).to eq([%w[t1], false, "assertion"])
  end

  it "marks mutants of load-only lines ran at load, without forking" do
    subject = subjects_in("class LoadOnlyTarget\n  def m(a)\n    b = a + 1\n    REGISTRY << b\n    b\n  end\nend\n")
              .first
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => %w[t1] } },
                                               tests: %w[t1], durations: { "t1" => 0.1 },
                                               load_lines: { subject.file => [4] })
    edit = edit_around(subject, "REGISTRY << b")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
    scheduler = scheduler_for(map)
    allow(scheduler).to receive(:load_problem).and_return([nil, nil])
    expect(runner).not_to receive(:run)
    results = scheduler.call(subject, [[mutation, subject.source]])
    expect(results.map(&:status)).to eq([:ran_at_load])
    expect(results.first.reason).to eq(Saboteur::Selection::CoverageMap::RAN_AT_LOAD)
  end

  it "checks each mutant separately after a stale capture, without checking unreachable verdicts" do
    subject = subjects_in("class UnreachTarget\n  def m(a)\n    a + 1\n  end\nend\n").first
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => %w[t1] } },
                                               tests: %w[t1], durations: { "t1" => 0.1 })
    scheduler = scheduler_for(map)
    allow(scheduler).to receive(:load_problem).and_return([nil, nil])
    message = "a Method object captured before re-evaluation still calls the original (captured definition at f.rb:3)"
    allow(runner).to receive(:run).and_return(outcome(:unreachable, message: message))
    mutations = Array.new(2) do
      Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison",
                                             edits: [edit_around(subject, "+", replacement: "-")])
    end
    results = scheduler.call(subject, mutations.map { |mutation| [mutation, subject.source] })
    expect(results.map(&:status)).to eq(%i[unreachable unreachable])
    expect(results.last.reason).to eq(message)
    expect(runner).to have_received(:run).twice
    expect(diagnostics.warnings).to eq(["UnreachTarget#m: #{message}", "UnreachTarget#m: #{message}"])
  end

  it "re-evaluates the sig together with the def for sorbet-wrapped methods" do
    Object.send(:define_method, :sig) { |*, &| nil }
    subject = subject_named(
      "class SorbetSchedTarget\n  sig { params(a: Integer) }\n  def fee(a)\n    a + 1\n  end\nend\n",
      "SorbetSchedTarget#fee"
    )
    load subject.file
    SorbetSchedTarget.send(:alias_method, :unwrapped_fee, :fee)
    # The wrapper must live in a sorbet-runtime path: that is how the
    # scheduler recognizes it (see Execution::Wrapper).
    SorbetSchedTarget.module_eval("def fee(a) = unwrapped_fee(a)",
                                  "/gems/sorbet-runtime/lib/t.rb", 5) # rubocop:disable Style/EvalWithLocation
    stub_const("T::Utils", Module.new)
    allow(T::Utils).to receive(:signature_for_method).and_return(Object.new)
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 4 => %w[t1] } },
                                               tests: %w[t1], durations: { "t1" => 0.1 })
    prefixes = []
    allow(runner).to receive(:run) do |mutation: nil, eval_prefix: nil, **|
      prefixes << eval_prefix
      mutation ? outcome(:killed, failed_ids: ["t1"]) : outcome(:survived)
    end
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison",
                                                      edits: [edit_around(subject, "+", replacement: "-")])
    results = scheduler_for(map).call(subject, [[mutation, subject.source]])
    expect(results.map(&:status)).to eq([:killed])
    expect(prefixes.uniq).to eq(["sig { params(a: Integer) }"])
  ensure
    Object.send(:remove_method, :sig) if Object.method_defined?(:sig)
  end
  it "marks a wholly load-only subject ran at load and keeps edited-line boundaries" do
    subject = subjects_in("class WholeLoad\n  def m(a)\n    a + 1\n    a * 2\n  end\nend\n").first
    map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: [], load_lines: { subject.file => [3] })
    scheduler = scheduler_for(map)
    allow(scheduler).to receive(:load_problem).and_return([nil, nil])
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit_around(subject, "+")])
    expect(scheduler.call(subject, [[mutation, subject.source]]).first.status).to eq(:ran_at_load)
    plan = described_class::Plan.new(subject: subject)
    other = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                   edits: [edit_around(subject, "*")])
    expect(scheduler.send(:uncoverable, plan, other, subject.source).status).to eq(:skipped)
  end

  it "does not attach sig text or warn for an ordinary method" do
    subject = subject_named("class PlainPrefix\n  sig { void }\n  def m; end\nend\n", "PlainPrefix#m")
    plan = described_class::Plan.new(subject: subject, wrapper: nil)
    expect(scheduler_for(nil).send(:eval_prefix, plan)).to be_nil
    expect(diagnostics.warnings).to be_empty
  end

  it "passes a sig to the unchanged timeout calibration run" do
    subject = subject_named("class TimeoutSig\n  sig { void }\n  def m; end\nend\n", "TimeoutSig#m")
    plan = described_class::Plan.new(subject: subject, wrapper: :sorbet, slowdown: 1.0)
    scheduler = scheduler_for(nil)
    expect(runner).to receive(:run).with(subject: subject, text: subject.source, test_ids: ["t1"],
                                         timeout: 300.0, eval_prefix: "sig { void }")
                                   .and_return(outcome(:killed))
    scheduler.send(:calibrate, plan, nil, subject.source, ["t1"], 5)
  end

  it "keeps the signature prefix on a calibrated mutant retry" do
    subject = subject_named("class RetrySig\n  sig { void }\n  def m; end\nend\n", "RetrySig#m")
    map = double("map", recorded_runtime: 1.0)
    plan = described_class::Plan.new(subject: subject, wrapper: :sorbet, slowdown: 1.0)
    scheduler = scheduler_for(map)
    expect(runner).to receive(:run).with(subject: subject, text: subject.source, test_ids: ["t1"],
                                         timeout: 300.0, eval_prefix: "sig { void }")
                                   .and_return(outcome(:survived))
    expect(runner).to receive(:run).with(subject: subject, text: "changed", test_ids: ["t1"],
                                         timeout: 5.0, mutation: :probe, eval_prefix: "sig { void }")
                                   .and_return(outcome(:killed))
    expect(scheduler.send(:calibrate, plan, :probe, "changed", ["t1"], 1).status).to eq(:killed)
  end

  it "does not let an unreachable mutant hide a later direct-route kill" do
    subject = subjects_in("class MixedRoutes\n  def m(a)\n    a + 1\n  end\nend\n").first
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => ["t1"] } }, tests: ["t1"])
    scheduler = scheduler_for(map)
    allow(scheduler).to receive(:load_problem).and_return([nil, nil])
    mutations = ["-", "*"].map do |replacement|
      Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "arithmetic",
                                             edits: [edit_around(subject, "+", replacement: replacement)])
    end
    allow(runner).to receive(:run).and_return(outcome(:unreachable), outcome(:killed, failed_ids: ["t1"]),
                                              outcome(:survived))
    expect(scheduler.call(subject, mutations.map { |mutation| [mutation, subject.source] }).map(&:status))
      .to eq(%i[unreachable killed])
    expect(runner).to have_received(:run).exactly(3).times
  end

  it "skips a Sorbet wrapper if its signature cannot be preserved" do
    subject = subjects_in("class MissingSignature\n  def m(a)\n    a + 1\n  end\nend\n").first
    scheduler = scheduler_for(nil)
    allow(scheduler).to receive(:load_problem).and_return([nil, :sorbet])
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "arithmetic",
                                                      edits: [edit_around(subject, "+", replacement: "-")])
    expect(runner).not_to receive(:run)
    result = scheduler.call(subject, [[mutation, subject.source]]).first
    expect(result.status).to eq(:skipped)
    expect(result.reason).to include("cannot preserve runtime type checks")
  end
end
