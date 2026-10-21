# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe "rejected kill accounting" do
  let(:subject_under_test) { subjects_in("class Counted\n  def m\n    1\n  end\nend\n").first }
  let(:mutation) { Saboteur::MutationSource::Builtin.new.mutations_for(subject_under_test).first }

  def result(status: :killed, killed_by: ["t1"], reused: false)
    Saboteur::MutantResult.new(subject: subject_under_test, mutation: mutation, status: status,
                               mutated_source: "nil", killed_by: killed_by, covered_by: ["t1"], reused: reused)
  end

  def reject(results)
    outcome = Saboteur::Execution::Runner::Outcome.new(status: :killed, runtime: 0.1)
    Saboteur::Engine::VerdictCheck.new(run_unchanged: ->(*) { outcome }, baseline_timeout: 1).call(results)
  end

  it "counts rejected named and unnamed kills, not other errors or accepted and reused kills" do
    results = reject([result, result(killed_by: []), result(status: :error), result(reused: true)])
    report = Saboteur::Report.new(results: results, subjects: [subject_under_test], wall_time: 0.1, root: Dir.pwd)
    expect(results.map(&:rejected_kill?)).to eq([true, true, false, false])
    expect(report.rejected_kills).to eq(2)
    expect(report.counts[:error]).to eq(3)
    expect(report.counts[:killed]).to eq(1)
    expect(report.score).to eq(1.0)
    terminal = StringIO.new
    Saboteur::Reporter::Terminal.new(terminal, verbose: true).call(report)
    expect(terminal.string).to include("kills rejected by unchanged-method check: 2")
    expect(Saboteur::Reporter::Stryker.build(report)[:rejectedKills]).to eq(2)
  end

  # #375: a rejected kill is a verdict (the tests fail with the method
  # unchanged), not a tool error - report.json must flag it per mutant,
  # not only in the aggregate count.
  it "flags each rejected kill per mutant in report.json" do
    results = reject([result, result(status: :error, killed_by: ["t1"])])
    report = Saboteur::Report.new(results: results, subjects: [subject_under_test], wall_time: 0.1, root: Dir.pwd)
    mutants = Saboteur::Reporter::Stryker.build(report)[:files].values.flat_map { |file| file[:mutants] }
    expect(mutants.map { |mutant| mutant[:rejectedKill] }).to eq([true, nil])
    expect(mutants.first[:status]).to eq("RuntimeError")
    expect(mutants.first[:statusReason]).to include("also fails with the method unchanged")
  end

  # #375: the summary names rejected kills as such instead of folding them
  # into a generic error count and section.
  it "names rejected kills in the summary instead of listing them as generic errors" do
    results = reject([result, result])
    report = Saboteur::Report.new(results: results, subjects: [subject_under_test], wall_time: 0.1, root: Dir.pwd)
    terminal = StringIO.new
    Saboteur::Reporter::Terminal.new(terminal).call(report)
    expect(terminal.string).to include("2 errors (2 rejected kills)")
    expect(terminal.string).to include("Rejected kills (tests also fail with the method unchanged")
    expect(terminal.string).not_to include("Errors (not counted as killed):")
  end

  it "prints one line per rejected kill under the rejected heading (#429)" do
    results = reject([result])
    report = Saboteur::Report.new(results: results, subjects: [subject_under_test], wall_time: 0.1, root: Dir.pwd)
    terminal = StringIO.new
    Saboteur::Reporter::Terminal.new(terminal).call(report)
    section = terminal.string.split("Rejected kills", 2).last
    expect(section).to include("Counted#m")
    expect(section).to include("also fails with the method unchanged")
  end

  it "keeps genuine errors in the error section when both kinds occur" do
    results = reject([result, result(status: :error, killed_by: ["t1"])])
    results.last.as_error("boom") # keep the flag off; as_error returns a copy
    report = Saboteur::Report.new(results: results, subjects: [subject_under_test], wall_time: 0.1, root: Dir.pwd)
    terminal = StringIO.new
    Saboteur::Reporter::Terminal.new(terminal).call(report)
    expect(terminal.string).to include("2 errors (1 rejected kill)")
    expect(terminal.string).to include("Rejected kills (tests also fail with the method unchanged")
    expect(terminal.string).to include("Errors (not counted as killed):")
  end

  it "reports zero when no kills were rejected" do
    report = Saboteur::Report.new(results: [result], subjects: [], wall_time: 0.1, root: Dir.pwd)
    expect(report.rejected_kills).to eq(0)
    terminal = StringIO.new
    Saboteur::Reporter::Terminal.new(terminal, verbose: true).call(report)
    expect(terminal.string).to include("kills rejected by unchanged-method check: 0")
    expect(Saboteur::Reporter::Stryker.build(report)[:rejectedKills]).to eq(0)
  end

  it "preserves rejection metadata across parallel worker encoding and reconstruction" do
    rejected = reject([result]).first
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    distribution = Saboteur::Engine::Distribution.new(jobs: 2, scheduler: nil, diagnostics: diagnostics, cache: nil)
    list = [[mutation, "nil"]]
    encoded = distribution.send(:encode, rejected, list)
    rebuilt = distribution.send(:rebuild, { "warnings" => [], "results" => [encoded] }, subject_under_test, list)
    expect(rebuilt.first.rejected_kill?).to be(true)
  end

  it "carries what ran across workers and through a rejection, and knows when a mutant is complete" do
    ran = Saboteur::MutantResult.new(subject: subject_under_test, mutation: mutation, status: :killed,
                                     mutated_source: "nil", killed_by: ["t1"], covered_by: %w[t1 t2],
                                     executed: ["t1"])
    expect([ran.complete?, ran.as_error("x").executed]).to eq([false, ["t1"]])
    all = Saboteur::MutantResult.new(subject: subject_under_test, mutation: mutation, status: :survived,
                                     mutated_source: "nil", covered_by: %w[t1 t2], executed: %w[t2 t1])
    expect(all.complete?).to be(true)
    expect(result.complete?).to be(false)
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    distribution = Saboteur::Engine::Distribution.new(jobs: 2, scheduler: nil, diagnostics: diagnostics, cache: nil)
    list = [[mutation, "nil"]]
    rebuilt = distribution.send(:rebuild, { "warnings" => [], "results" => [distribution.send(:encode, ran, list)] },
                                subject_under_test, list)
    expect(rebuilt.first.executed).to eq(["t1"])
  end
end
