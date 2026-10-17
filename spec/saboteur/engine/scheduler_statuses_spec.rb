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

  # A def-time macro (rolify's deprecate shape, #409): the block-body
  # lines ARE covered - by the pristine closure the load-time caller
  # captured - so line evidence cannot see that no post-boot call exists.
  # The boot's method counters can: the def ran only while loading.
  it "marks a macro's mutants ran at load when only the boot called its def, without forking" do
    subject = subjects_in("module Utils\n  def deprecate(old_m, new_m)\n    " \
                          "define_method(old_m) { |*a| send(new_m, *a) }\n  end\nend\n").first
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => %w[t1] } },
                                               tests: %w[t1], durations: { "t1" => 0.1 },
                                               load_methods: { subject.file => [2] })
    edit = edit_around(subject, "send(new_m, *a)")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
    scheduler = scheduler_for(map)
    allow(scheduler).to receive(:load_problem).and_return([nil, nil])
    expect(runner).not_to receive(:run)
    results = scheduler.call(subject, [[mutation, subject.source]])
    expect(results.map(&:status)).to eq([:ran_at_load])
    expect(results.first.reason).to eq(Saboteur::Selection::CoverageMap::RAN_AT_LOAD)
  end

  # A constant is observable: re-evaluating the whole file replaces the
  # object test-time readers see, so its mutants must run even when the
  # assignment's line carries load-only evidence (#409 guard).
  it "runs a constant's mutants even when the constant's line reads load-only" do
    dir = Dir.mktmpdir("saboteur-spec-")
    (@subject_dirs ||= []) << dir
    path = File.join(File.realpath(dir), "constants.rb")
    File.write(path, "FLAGS = { a: 1 }.freeze\n")
    subject = Saboteur::ConstantSubjectFinder.new.call(path).subjects.first
    subject.consumer_lines = { subject.file => [1] }
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 1 => %w[t1] } },
                                               tests: %w[t1], durations: { "t1" => 0.1 },
                                               load_methods: { subject.file => [subject.start_line] })
    edit = edit_around(subject, "a: 1")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
    scheduler = scheduler_for(map)
    allow(scheduler).to receive(:load_problem).and_return([nil, nil])
    allow(runner).to receive(:run).and_return(outcome(:survived), outcome(:survived))
    results = scheduler.call(subject, [[mutation, subject.source]])
    expect(results.map(&:status)).to eq([:survived])
  end
  it "runs mutants of a boot-called def that tests call again post-boot" do
    subject = subjects_in("module Utils\n  def helper(a)\n    a + 1\n  end\nend\n").first
    map = Saboteur::Selection::CoverageMap.new(lines: { subject.file => { 3 => %w[t1] } },
                                               tests: %w[t1], durations: { "t1" => 0.1 },
                                               methods: { subject.file => { 2 => %w[t1] } },
                                               load_methods: { subject.file => [2] })
    edit = edit_around(subject, "+")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
    scheduler = scheduler_for(map)
    allow(scheduler).to receive(:load_problem).and_return([nil, nil])
    allow(runner).to receive(:run).and_return(outcome(:survived), outcome(:survived))
    results = scheduler.call(subject, [[mutation, subject.source]])
    expect(results.map(&:status)).to eq([:survived])
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

  it "caps the verdict check at the remaining --max-duration budget (#245)" do
    subject = subject_named("class CappedCheck\n  def m; end\nend\n", "CappedCheck#m")
    plan = described_class::Plan.new(subject: subject, wrapper: nil)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison",
                                                      edits: [Saboteur::MutationSource::Edit.new(
                                                        file: subject.file, start_byte: 0, end_byte: 1, replacement: "2"
                                                      )])
    result = Saboteur::MutantResult.new(subject: subject, mutation: mutation, mutated_source: "x", status: :killed,
                                        covered_by: ["t1"], killed_by: ["t1"], runtime: 0.1)
    scheduler = scheduler_for(nil)
    scheduler.instance_variable_set(:@deadline, 600.0)
    allow(Process).to receive(:clock_gettime).and_return(500.0)
    expect(runner).to receive(:run).with(subject: subject, text: subject.source, test_ids: ["t1"],
                                         timeout: 100.0, eval_prefix: nil)
                                   .and_return(outcome(:survived))
    scheduler.send(:checked, plan, [result])
  end

  it "caps calibration admissions at the remaining --max-duration budget (#245)" do
    subject = subject_named("class CappedCal\n  def m; end\nend\n", "CappedCal#m")
    map = double("map", recorded_runtime: 1.0)
    plan = described_class::Plan.new(subject: subject, wrapper: nil, slowdown: 1.0)
    scheduler = scheduler_for(map)
    scheduler.instance_variable_set(:@deadline, 600.0)
    allow(Process).to receive(:clock_gettime).and_return(500.0)
    expect(runner).to receive(:run).with(subject: subject, text: subject.source, test_ids: ["t1"],
                                         timeout: 100.0, eval_prefix: nil)
                                   .and_return(outcome(:survived))
    expect(runner).to receive(:run).with(subject: subject, text: "changed", test_ids: ["t1"],
                                         timeout: 5.0, mutation: :probe, eval_prefix: nil)
                                   .and_return(outcome(:killed))
    expect(scheduler.send(:calibrate, plan, :probe, "changed", ["t1"], 1).status).to eq(:killed)
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

  # The defined-order retry's mutant run needs the same sorbet sig preamble
  # as every other fork of a wrapped method: without it the child evaluates
  # the def alone and runtime type checks silently drop (#579 dogfood).
  it "passes the sig to the defined-order retry's mutant run" do
    subject = subject_named("class RetrySig\n  sig { void }\n  def m; end\nend\n", "RetrySig#m")
    plan = described_class::Plan.new(subject: subject, wrapper: :sorbet, slowdown: 1.0)
    mut = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                 edits: [edit_around(subject, "m")])
    result = Saboteur::MutantResult.new(subject: subject, mutation: mut, status: :error,
                                        mutated_source: subject.source, rejected_kill: true,
                                        covered_by: ["./spec/retry_sig_spec.rb[1:2]"])
    tests = ["./spec/retry_sig_spec.rb[1:1]", "./spec/retry_sig_spec.rb[1:2]"]
    map = Saboteur::Selection::CoverageMap.new(lines: {}, tests: tests,
                                               durations: tests.to_h { |id| [id, 0.1] })
    scheduler = scheduler_for(map)
    prefixes = []
    allow(runner).to receive(:run) do |mutation: nil, eval_prefix: nil, **|
      prefixes << eval_prefix if mutation
      outcome(:survived)
    end
    scheduler.send(:retried_in_defined_order, plan, result)
    expect(prefixes).to eq(["sig { void }"])
  end
end
