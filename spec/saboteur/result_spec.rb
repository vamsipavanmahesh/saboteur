# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Report do
  let(:report) do
    report_of(result_for(:killed, runtime: 0.2), result_for(:killed, replacement: "<=", runtime: 0.4),
              result_for(:survived, replacement: "==", runtime: 0.3),
              result_for(:timeout, replacement: "!=", runtime: 5.0),
              result_for(:error, replacement: "<", runtime: 0.1),
              result_for(:skipped, replacement: ">", reason: "no coverage"))
  end

  it "counts every status separately" do
    expect(report.counts).to eq(killed: 2, survived: 1, timeout: 1, error: 1, skipped: 1)
  end

  it "scores (killed + timeout) / (killed + survived + timeout), leaving errors and skips out" do
    expect(report.score).to eq(3.0 / 4)
  end

  it "has no score when nothing was tested" do
    expect(report_of(result_for(:error)).score).to be_nil
  end

  it "averages runtime over executed mutants only" do
    expect(report.mean_runtime).to be_within(1e-9).of((0.2 + 0.4 + 0.3 + 5.0 + 0.1) / 5)
  end

  it "groups skip reasons" do
    expect(report.skip_reasons).to eq("no coverage" => 1)
  end

  it "separates ignored survivors" do
    survivor = report.survivors.first
    survivor.ignored = "equivalent"
    expect(report.unignored_survivors).to be_empty
  end
end

RSpec.describe Saboteur::MutantResult do
  it "rejects unknown statuses" do
    expect { result_for(:passed) }.to raise_error(ArgumentError, /unknown status/)
  end

  it "has a stable digest for the ignore list" do
    expect(result_for(:survived).digest).to eq(result_for(:killed).digest)
    expect(result_for(:survived).digest).not_to eq(result_for(:survived, replacement: "<=").digest)
  end

  it "renders a whole-line diff relative to the root" do
    diff = result_for(:survived).diff(root: File.dirname(person_subject.file))
    expect(diff).to include("--- a/person.rb", "-  def adult?; @age >= 18; end", "+  def adult?; @age > 18; end")
  end
end
