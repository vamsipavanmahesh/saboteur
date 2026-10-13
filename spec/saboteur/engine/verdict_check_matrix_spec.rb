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
end
