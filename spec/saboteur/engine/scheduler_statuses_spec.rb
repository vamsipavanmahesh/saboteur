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

  it "marks every mutant unreachable after the first stale capture: forks once, warns once, checks no verdict" do
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
    expect(runner).to have_received(:run).once
    expect(diagnostics.warnings).to eq(["UnreachTarget#m: #{message}"])
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
end
