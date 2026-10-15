# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# A matrix run lists every failing test as a killer. Each one has to pass
# under the unchanged method, in the same sequence, or the kill is rejected.
RSpec.describe Saboteur::Engine::VerdictCheck, "with several killers" do
  let(:subject_under_test) { subjects_in("class Multi\n  def m\n    1\n  end\nend\n").first }
  let(:mutation) { Saboteur::MutationSource::Builtin.new.mutations_for(subject_under_test).first }
  let(:sequences) { [] }

  def result(killed_by:, covered_by: %w[t1 t2 t3])
    Saboteur::MutantResult.new(subject: subject_under_test, mutation: mutation, status: :killed,
                               mutated_source: "nil", killed_by: killed_by, covered_by: covered_by)
  end

  # run_unchanged fails as soon as the sequence reaches a test in failing_at.
  def check(results, failing_at: [])
    run = lambda do |tests, _timeout|
      sequences << tests
      failed = tests.intersect?(failing_at)
      Saboteur::Execution::Runner::Outcome.new(status: failed ? :killed : :survived, runtime: 0.1,
                                               message: failed ? "boom" : nil)
    end
    described_class.new(run_unchanged: run, baseline_timeout: 1).call(results)
  end

  it "checks the sequence through the last killer, whatever order killed_by lists them" do
    check([result(killed_by: %w[t3 t1])])
    expect(sequences).to eq([%w[t1 t2 t3]])
  end

  it "rejects a kill when a later listed killer also fails with the method unchanged" do
    checked = check([result(killed_by: %w[t1 t3])], failing_at: %w[t3]).first
    expect([checked.status, checked.rejected_kill?]).to eq([:error, true])
    expect(checked.reason).to eq("killing test t3 also fails with the method unchanged: boom")
  end

  it "keeps a complete multi-killer kill when every test passes unchanged" do
    expect(check([result(killed_by: %w[t1 t3])]).first.status).to eq(:killed)
  end

  it "keeps a kill by a subset of the planned tests, checking only through its last killer" do
    expect(check([result(killed_by: %w[t2])]).first.status).to eq(:killed)
    expect(sequences).to eq([%w[t1 t2]])
  end

  it "checks the killer alone when it is not among the planned tests" do
    check([result(killed_by: %w[other])])
    expect(sequences).to eq([%w[other]])
  end

  it "checks only the first killer when none of several is among the planned tests" do
    check([result(killed_by: %w[other another])])
    expect(sequences).to eq([%w[other]])
  end

  it "ignores killers outside the planned tests when finding the last position" do
    check([result(killed_by: %w[other t2])])
    expect(sequences).to eq([%w[t1 t2]])
  end

  # The budget can stop a check before it forks or cut its admission short;
  # the run_unchanged side reports that as :unverified. That is not a
  # rejection: the check never got its answer (#296).
  it "marks a kill unverified when the budget stops its check, not a rejected kill" do
    run = lambda do |_tests, _timeout|
      Saboteur::Execution::Runner::Outcome.new(status: :unverified, runtime: 0.0,
                                               message: "the --max-duration budget is spent")
    end
    checked = described_class.new(run_unchanged: run, baseline_timeout: 1).call([result(killed_by: %w[t1])]).first
    expect([checked.status, checked.rejected_kill?]).to eq([:unverified, false])
    expect(checked.reason).to eq("the --max-duration budget is spent")
  end

  it "marks an unnamed kill unverified when the budget stops its check" do
    run = ->(_tests, _timeout) { Saboteur::Execution::Runner::Outcome.new(status: :unverified, runtime: 0.0) }
    checked = described_class.new(run_unchanged: run, baseline_timeout: 1).call([result(killed_by: [])]).first
    expect(checked.status).to eq(:unverified)
  end

  it "still checks later sequences after a budget-stopped one: each gets its own admission" do
    first = result(killed_by: %w[t1])
    second = result(killed_by: %w[t3])
    run = lambda do |tests, _timeout|
      status = tests == %w[t1] ? :unverified : :survived
      Saboteur::Execution::Runner::Outcome.new(status: status, runtime: 0.1)
    end
    checked = described_class.new(run_unchanged: run, baseline_timeout: 1).call([first, second])
    expect(checked.map(&:status)).to eq(%i[unverified killed])
  end
end

# A re-run the budget stopped proves nothing: the kill is unverified, and
# the verdict keeps the runner's own reason for it (#296).
RSpec.describe Saboteur::Engine::VerdictCheck, "when the budget stops a check" do
  let(:subject_under_test) { subjects_in("class Multi\n  def m\n    1\n  end\nend\n").first }
  let(:mutation) { Saboteur::MutationSource::Builtin.new.mutations_for(subject_under_test).first }

  def result(killed_by:, covered_by: %w[t1 t2])
    Saboteur::MutantResult.new(subject: subject_under_test, mutation: mutation, status: :killed,
                               mutated_source: "nil", killed_by: killed_by, covered_by: covered_by)
  end

  def check_with(results, outcome)
    described_class.new(run_unchanged: ->(_tests, _timeout) { outcome }, baseline_timeout: 1).call(results)
  end

  def outcome(status, message = nil)
    Saboteur::Execution::Runner::Outcome.new(status: status, runtime: 0.1, message: message)
  end

  it "marks a named kill unverified with the runner's own reason" do
    checked = check_with([result(killed_by: %w[t1])], outcome(:unverified, "the --max-duration budget is spent")).first
    expect([checked.status, checked.reason]).to eq([:unverified, "the --max-duration budget is spent"])
  end

  it "falls back to the budget reason when the unverified re-run has no message" do
    checked = check_with([result(killed_by: %w[t1])], outcome(:unverified)).first
    expect(checked.reason).to eq(described_class::BUDGET_REASON)
  end

  it "marks an unnamed kill unverified with the runner's own reason" do
    checked = check_with([result(killed_by: [])], outcome(:unverified, "the budget cut the check short")).first
    expect([checked.status, checked.reason]).to eq([:unverified, "the budget cut the check short"])
  end

  # The unchecked map's value is the message: a nil message must still mark
  # the kill unverified (with the generic reason), never leave it killed.
  it "marks an unnamed kill unverified with the generic reason when the run gave no message (#296)" do
    checked = check_with([result(killed_by: [])], outcome(:unverified)).first
    expect([checked.status, checked.reason]).to eq([:unverified, described_class::BUDGET_REASON])
  end

  it "keeps an unnamed kill whose unchanged run passes and rejects one whose run fails" do
    expect(check_with([result(killed_by: [])], outcome(:survived)).first.status).to eq(:killed)
    rejected = check_with([result(killed_by: [])], outcome(:killed, "boom")).first
    expect([rejected.status, rejected.rejected_kill?]).to eq([:error, true])
  end
end
