# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe "reporting skipped subjects" do
  let(:subject_under_test) { subjects_in("class K\n  def m\n    1\n  end\nend\n").first }
  let(:report) do
    Saboteur::Report.new(results: [], subjects: [subject_under_test], wall_time: 0,
                         root: File.dirname(subject_under_test.file),
                         skipped_subjects: { subject_under_test => "no coverage" })
  end

  it "reports subject skips separately from mutant counts and the score" do
    output = StringIO.new
    Saboteur::Reporter::Terminal.new(output, verbose: true).call(report)
    expect(output.string).to include("1 subject, 0 mutants", "methods never run by tests: 1", "K#m", "Score: n/a")
    expect(report.counts[:skipped]).to eq(0)
  end

  it "prints other subject skip reasons with the generic wording (#1087)" do
    other = Saboteur::Report.new(results: [], subjects: [subject_under_test], wall_time: 0,
                                 root: File.dirname(subject_under_test.file),
                                 skipped_subjects: { subject_under_test => "filtered" })
    output = StringIO.new
    Saboteur::Reporter::Terminal.new(output, verbose: true).call(other)
    expect(output.string).to include("skipped subjects: filtered: 1\n")
  end

  it "adds subject skip details to JSON without inventing mutant entries" do
    json = Saboteur::Reporter::Stryker.build(report)
    expect(json[:files]).to be_empty
    expect(json[:skippedSubjects]).to eq([{ subject: "K#m", file: File.basename(subject_under_test.file),
                                            line: 2, reason: "no coverage" }])
  end
end

RSpec.describe Saboteur::Reporter::Stryker, "candidate selection warnings" do
  it "keeps omitted-count warnings in machine-readable output" do
    report = report_of(warnings: ["K#m: omitted 3 mutant(s) above max_mutants_per_method (2)"])
    expect(described_class.build(report)[:warnings]).to eq(report.warnings)
  end
end
