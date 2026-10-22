# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"

RSpec.describe Saboteur::Reporter::Agent, "pins" do
  def provenance_with(**changes)
    described_class::Provenance.new(
      ref: "origin/main", seed: 7, head: "abc1234", working_tree: "clean", changed_files: 0, mode: "diff",
      json_report: ".saboteur/report.json", subjects: [], tests: [], sources: [], config_path: nil,
      digest: nil, cache: true, incremental: false, settings: {}, **changes
    )
  end

  def finding_with(**changes)
    { digest: "d" * 16, path: "lib/a.rb", line: 3, endLine: 3, subject: "A#b", operator: "comparison",
      original: ">=", replacement: ">", coarse: false, edits: [] }.merge(changes)
  end

  def with_findings(*findings)
    allow(Saboteur::Reporter::Findings).to receive(:build)
      .and_return(survivors: findings, survivorsTruncated: 0, accepted: [], acceptedTruncated: 0, ordering: "order")
  end

  let(:report) { report_of(result_for(:survived)) }

  it "renders the payload as pretty JSON with one trailing newline" do
    expect(described_class.render({ a: 1, b: [2] })).to eq("{\n  \"a\": 1,\n  \"b\": [\n    2\n  ]\n}\n")
  end

  it "shows no findings in the minimal payload and keeps the incomplete reasons as reason then count" do
    with_findings(finding_with)
    small = described_class.send(:minimal, report, provenance_with)
    expect(small[:findings][:shown]).to eq([])
    skipped = report_of(result_for(:survived), result_for(:skipped, replacement: "<"))
    incomplete = described_class.send(:minimal, skipped, provenance_with)[:incomplete]
    expect(incomplete).not_to be_empty
    incomplete.each { |reason| expect(reason.keys).to eq(%i[reason count]) }
  end

  it "points the replay command at the first listed survivor" do
    with_findings(finding_with(digest: "1" * 16), finding_with(digest: "2" * 16))
    steps = described_class.call(report, provenance_with)[:next]
    expect(steps[:replay]).to include("1" * 16)
    expect(steps[:replay]).not_to include("2" * 16)
  end

  it "narrows the payload's replay command to the survivor's covering spec files (#1148)" do
    survivor = result_for(:survived, covered_by: ["./spec/person_spec.rb[1:3]"])
    report = report_of(survivor)
    with_findings(finding_with(digest: survivor.digest))
    steps = described_class.call(report, provenance_with(tests: %w[spec/a_spec.rb spec/b_spec.rb]))[:next]
    words = Shellwords.split(steps[:replay])
    expect(words.each_cons(2).to_a).to include(["--test", "spec/person_spec.rb"])
    expect(words).not_to include("spec/a_spec.rb", "spec/b_spec.rb")
  end

  it "clips a number that is too long for the budget to its first digits" do
    big = 10**30
    seed = described_class.call(report, provenance_with(seed: big))[:provenance][:seed]
    expect(seed).to eq("#{big.to_s[0, 20]}...")
  end

  it "leaves out an empty setting the command line did not type" do
    steps = described_class.call(report, provenance_with(settings: { operators: [], jobs: 4 }))[:next]
    expect(steps[:rerun]).to eq("saboteur run --agent --since origin/main --jobs 4 --seed 7")
    typed = provenance_with(settings: { operators: [], jobs: 4 }, typed_settings: [:operators])
    expect(described_class.call(report, typed)[:next][:rerun])
      .to eq("saboteur run --agent --since origin/main --jobs 4 --operators '' --seed 7")
  end
end
