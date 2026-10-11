# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "tmpdir"

RSpec.describe Saboteur::Reporter::Stryker do
  let(:report) do
    survivor = result_for(:survived, replacement: "==", runtime: 0.01)
    survivor.ignored = "equivalent"
    report_of(result_for(:killed, runtime: 0.25, killed_by: ["t1"], covered_by: %w[t1 t2]),
              survivor,
              result_for(:timeout, replacement: "<"), result_for(:error, replacement: "<=", reason: "boom\nmore"),
              result_for(:skipped, replacement: "!=", reason: "no coverage"),
              result_for(:skipped, replacement: "!=", reason: "baseline failure"))
  end
  let(:json) { JSON.parse(JSON.generate(described_class.build(report))) }
  let(:mutants) { json.dig("files", "person.rb", "mutants") }

  it "writes schema version 2 with one entry per file, holding the full source" do
    expect(json["schemaVersion"]).to eq("2")
    expect(json["files"].keys).to eq(["person.rb"])
    expect(json.dig("files", "person.rb", "source")).to eq(ReportHelpers::PERSON)
    expect(json.dig("files", "person.rb", "language")).to eq("ruby")
  end

  it "records the seed, so the run can be repeated" do
    expect(json["config"]).to eq("seed" => 1)
  end

  it "maps every saboteur status to a distinct schema status" do
    expect(mutants.map { |m| m["status"] })
      .to eq(%w[Killed Survived Timeout RuntimeError NoCoverage Ignored])
  end

  it "records 1-based positions, the replacement, tests and duration" do
    killed = mutants.first
    expect(killed["location"]).to eq("start" => { "line" => 2, "column" => 20 },
                                     "end" => { "line" => 2, "column" => 22 })
    expect(killed.values_at("mutatorName", "replacement", "killedBy", "coveredBy", "duration"))
      .to eq(["comparison", ">", ["0"], %w[0 1], 250])
    expect(killed["id"]).to match(/\A\h{16}\z/)
  end

  it "lists each test once under testFiles, grouped by spec file" do
    report = report_of(result_for(:killed, killed_by: ["./spec/a_spec.rb[1:1]"],
                                           covered_by: ["./spec/a_spec.rb[1:1]", "./spec/b_spec.rb[2]"]))
    json = JSON.parse(JSON.generate(described_class.build(report)))
    expect(json["testFiles"]).to eq(
      "spec/a_spec.rb" => { "tests" => [{ "id" => "0", "name" => "./spec/a_spec.rb[1:1]" }] },
      "spec/b_spec.rb" => { "tests" => [{ "id" => "1", "name" => "./spec/b_spec.rb[2]" }] }
    )
  end

  it "says what killed a killed mutant: an assertion or a crash" do
    report = report_of(result_for(:killed, kill_cause: "assertion"), result_for(:killed, kill_cause: "TypeError"))
    reasons = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants")
                  .map { |m| m["statusReason"] }
    expect(reasons).to eq(["assertion", "crash: TypeError"])
  end

  it "maps a resource-limit stop to RuntimeError with its reason" do
    report = report_of(result_for(:resource_limit, reason: "process tree grew by 3000 MB (limit 2048 MB)"))
    mutant = JSON.parse(JSON.generate(described_class.build(report))).dig("files", "person.rb", "mutants").first
    expect(mutant.values_at("status", "statusReason"))
      .to eq(["RuntimeError", "resource limit: process tree grew by 3000 MB (limit 2048 MB)"])
  end

  it "keeps ignored survivors as Survived with the reason, and first lines of errors" do
    expect(mutants[1]["statusReason"]).to eq("ignored: equivalent")
    expect(mutants[3]["statusReason"]).to eq("boom")
  end

  it "carries the bounded findings a code-review surface annotates from" do
    findings = json.fetch("saboteur").fetch("findings")
    expect(findings["version"]).to eq(1)
    expect(findings["survivors"]).to eq([])
    expect(findings["accepted"].map { |finding| finding["reason"] }).to eq(["equivalent"])
  end

  it "writes the file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out", "report.json")
      described_class.new(path).call(report)
      expect(JSON.parse(File.read(path))["schemaVersion"]).to eq("2")
    end
  end
end
