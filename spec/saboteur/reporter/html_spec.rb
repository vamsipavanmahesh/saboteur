# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Reporter::Html do
  let(:report) do
    test_id = "./spec/person_spec.rb[1:1]"
    report_of(result_for(:killed, killed_by: [test_id], covered_by: [test_id]),
              result_for(:survived, replacement: "=="),
              result_for(:skipped, replacement: "!=", reason: "no coverage"),
              warnings: ["Person#adult?: omitted 3 mutant(s) above max_mutants_per_method (2)"])
  end
  let(:html) { described_class.build(report) }

  it "is one self-contained page with no external resources" do
    expect(html).to start_with("<!DOCTYPE html>")
    expect(html).not_to match(%r{(?:src|href)\s*=\s*["']?(?:https?:)?//}i)
    expect(html).not_to include("<script")
  end

  it "shows the score, the seed and a count for every status" do
    expect(html).to include("Mutation score: 50.0%", "seed 1")
    %w[Killed Survived NoCoverage].each { |status| expect(html).to include(status) }
  end

  it "lists each mutant with its operator, replacement and location" do
    expect(html).to include("comparison", "&gt;", "==", "person.rb", "line 2")
  end

  it "opens files that have survivors and shows the tests that killed a mutant" do
    expect(html).to include("<details open>")
    expect(html).to include("./spec/person_spec.rb[1:1]")
  end

  it "prints warnings and skipped subjects" do
    skipped = report_with_skipped_subject
    page = described_class.build(skipped)
    expect(page).to include("Skipped subjects", "no coverage", "K#m")
    expect(html).to include("omitted 3 mutant(s) above max_mutants_per_method (2)")
  end

  it "escapes source code and text so the page cannot run injected markup" do
    hostile = report_of(result_for(:survived, replacement: "<img src=x onerror=alert(1)>"),
                        warnings: ["<b>careful</b>"])
    page = described_class.build(hostile)
    expect(page).not_to include("<img src=x", "<b>careful")
    expect(page).to include("&lt;img src=x", "&lt;b&gt;careful")
  end

  it "says so when nothing was tested" do
    expect(described_class.build(report_of)).to include("Mutation score: n/a")
  end

  it "writes the page to the given path, creating folders" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "nested", "report.html")
      described_class.new(path).call(report)
      expect(File.read(path)).to eq(html)
    end
  end

  def report_with_skipped_subject
    subject_under_test = subjects_in("class K\n  def m\n    1\n  end\nend\n").first
    Saboteur::Report.new(results: [], subjects: [subject_under_test], wall_time: 0,
                         root: File.dirname(subject_under_test.file),
                         skipped_subjects: { subject_under_test => "no coverage" })
  end
end
