# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Reporter::Html, "seed and whole-body pins" do
  def unseeded(*results)
    Saboteur::Report.new(results: results, subjects: [person_subject], wall_time: 1.25,
                         root: File.dirname(person_subject.file))
  end

  it "leaves the seed out of the summary line when the run had none" do
    expect(described_class.build(unseeded(result_for(:killed))))
      .to include("(1 subject, 1 mutant, 1.2s)</p>\n")
  end

  it "shows the seed after the time when the run had one" do
    expect(described_class.build(report_of(result_for(:killed)))).to include("1.2s, seed 1)</p>\n")
  end

  it "prints no whole-body line when every mutant is whole-body" do
    page = described_class.build(report_of(result_for(:killed, coarse: true, kill_cause: "assertion")))
    expect(page).not_to include("Without whole-body mutants")
  end

  it "prints no whole-body line when no mutant is whole-body" do
    page = described_class.build(report_of(result_for(:killed, kill_cause: "assertion")))
    expect(page).not_to include("Without whole-body mutants")
  end

  it "prints the whole-body line with its split when the kill causes are known" do
    page = described_class.build(report_of(result_for(:killed, coarse: true, kill_cause: "assertion"),
                                           result_for(:killed, replacement: "<", kill_cause: "assertion"),
                                           result_for(:survived, replacement: "==")))
    expect(page).to include(
      "<p>Without whole-body mutants (body_nil, body_true, body_false, body_raise): 50.0% " \
      "(50.0% assertion, 0.0% crash) over 2 mutants. Whole-body mutants alone: 100.0% over 1.</p>\n"
    )
  end

  it "prints the whole-body line without a split when the kill causes are unknown" do
    page = described_class.build(report_of(result_for(:killed, coarse: true),
                                           result_for(:survived, replacement: "==")))
    expect(page).to include(
      "<p>Without whole-body mutants (body_nil, body_true, body_false, body_raise): 0.0% over 1 mutants. " \
      "Whole-body mutants alone: 100.0% over 1.</p>\n"
    )
    expect(page).not_to include("Of the tested mutants")
  end
end
