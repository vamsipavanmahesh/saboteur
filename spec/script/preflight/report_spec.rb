# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe Preflight::Report do
  let(:sha) { "a" * 40 }

  def result(status, name: "check", reason: nil)
    Preflight::CheckResult.new(name: name, status: status, reason: reason)
  end

  def report(results, mode: "full", before: "t1", after: "t1")
    options = Preflight::Options.new(base: sha, head: sha, base_ref: "main", mode: mode)
    described_class.new(options: options, merge_base: sha, results: results, run_id: "r", tree_before: before,
                        tree_after: after, environment: {}, changes: [])
  end

  it "reports automatic_checks_passed only for full mode with every check passed (valid control)" do
    expect([report([result(:passed)]).verdict,
            report([result(:passed)]).exit_code]).to eq(["automatic_checks_passed", 0])
  end

  it "reports fast mode as partial even when everything passed" do
    expect([report([result(:passed)], mode: "fast").verdict,
            report([result(:passed)], mode: "fast").exit_code]).to eq(["partial", 0])
  end

  it "reports full mode as partial while any check is not run" do
    expect(report([result(:passed), result(:not_run)]).verdict).to eq("partial")
  end

  it "reports a review_required notice as partial, never as a pass" do
    expect(report([result(:passed), result(:review_required)]).verdict).to eq("partial")
  end

  it "reports failed with exit 1 and incomplete with exit 3" do
    expect([report([result(:failed)]).exit_code, report([result(:incomplete)]).exit_code]).to eq([1, 3])
  end

  it "ranks an evidence gap above a finding, and keeps the finding listed" do
    r = report([result(:failed, name: "rubocop"), result(:incomplete, name: "report_output")])
    expect([r.verdict, r.exit_code, r.markdown]).to match(["incomplete", 3, /rubocop \| failed/])
  end

  it "is incomplete when a before or after identity is missing, even with a failure" do
    expect(report([result(:passed)], before: nil, after: nil).verdict).to eq("incomplete")
    expect(report([result(:failed)], before: "t1", after: nil).verdict).to eq("incomplete")
  end

  it "is incomplete when the inputs changed during the run" do
    expect(report([result(:passed)], after: "t2").verdict).to eq("incomplete")
  end

  it "puts changed inputs ahead of a failure and keeps the finding visible" do
    r = report([result(:failed, name: "rubocop")], after: "t2")
    expect([r.verdict, r.exit_code, r.markdown]).to match(["incomplete", 3, /rubocop/])
  end

  it "is incomplete with no results at all" do
    expect(report([]).verdict).to eq("incomplete")
  end

  it "never says approved or merge-ready and always lists manual obligations" do
    text = report([result(:passed)]).markdown + JSON.generate(report([result(:passed)]).to_h)
    expect(text).not_to match(/approved|merge-ready|panel-ready/i)
    expect(report([result(:passed)]).to_h[:manual_obligations]).not_to be_empty
  end

  it "labels base freshness as unverified" do
    expect(report([result(:passed)]).to_h[:base_freshness]).to start_with("unverified")
  end

  it "keeps hostile text from breaking the Markdown table" do
    markdown = report([result(:failed, name: "lint", reason: "bad | `x`\n# heading")]).markdown
    expect(markdown.lines.grep(/\| lint \|/).length).to eq(1)
    expect(markdown.lines.grep(/\| lint \|/).first).to match(/\A\| lint \| failed \| [^|`\n]*\|\n\z/)
  end

  it "writes JSON and Markdown" do
    Dir.mktmpdir do |directory|
      report([result(:passed)]).write(directory)
      expect(JSON.parse(File.read(File.join(directory, "report.json")))["verdict"]).to eq("automatic_checks_passed")
      expect(File.read(File.join(directory, "report.md"))).to start_with("# Preflight full")
    end
  end
end
