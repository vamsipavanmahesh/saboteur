# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"

# The agent JSON payload and the process exit codes are public APIs with a
# deprecation process (docs/stability.md). This contract fails when a key,
# the version or an exit code changes without a deliberate version bump.
RSpec.describe "agent output contract (docs/stability.md)" do
  def provenance
    Saboteur::Reporter::Agent::Provenance.new(
      ref: "origin/main", seed: 7, head: "abc1234", working_tree: "clean", changed_files: 0, mode: "all",
      json_report: ".saboteur/report.json", subjects: [], tests: [], sources: [], config_path: nil,
      digest: nil, cache: true, incremental: false, settings: {}
    )
  end

  def payload_for(report)
    JSON.parse(Saboteur::Reporter::Agent.render(Saboteur::Reporter::Agent.call(report, provenance)))
  end

  it "pins the payload version" do
    expect(Saboteur::Reporter::Agent::VERSION).to eq(1)
  end

  it "pins the exit codes" do
    expect([Saboteur::Reporter::Agent::EXIT_CLEAN, Saboteur::Reporter::Agent::EXIT_REVIEW,
            Saboteur::Reporter::Agent::EXIT_INVOCATION, Saboteur::Reporter::Agent::EXIT_INCOMPLETE])
      .to eq([0, 1, 2, 3])
    expect([Saboteur::CLI::EXIT_OK, Saboteur::CLI::EXIT_SURVIVORS, Saboteur::CLI::EXIT_USAGE,
            Saboteur::CLI::EXIT_TOOL, Saboteur::CLI::EXIT_BUDGET]).to eq([0, 1, 2, 3, 4])
  end

  it "pins the run payload's top-level keys and their order" do
    report = Saboteur::Report.new(results: [], subjects: [], wall_time: 0.1, root: "/tmp", seed: 7)
    expect(payload_for(report).keys).to eq(%w[version status verdict exitCode provenance counts score
                                              scoreDefinition incomplete timeoutCountedAsDetected findings
                                              warnings next])
  end

  it "pins the failure payload's keys" do
    expect(Saboteur::Reporter::Agent.failure("boom", 3).keys)
      .to eq(%i[version status verdict exitCode message next])
  end

  it "maps each status to its documented exit code" do
    clean = payload_for(report_of(result_for(:killed)))
    incomplete = payload_for(Saboteur::Report.new(results: [], subjects: [person_subject], wall_time: 1,
                                                  root: File.dirname(person_subject.file), seed: 7,
                                                  skipped_subjects: { person_subject => "no coverage" }))
    expect([clean.values_at("verdict", "exitCode"), incomplete.values_at("verdict", "exitCode")])
      .to eq([["clean", 0], ["incomplete", 3]])
  end
end
