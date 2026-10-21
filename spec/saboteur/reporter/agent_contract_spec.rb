# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"

# The agent JSON payload and the process exit codes are public APIs with a
# deprecation process (docs/stability.md). This contract fails when a pinned
# key, a status or verdict value, the version or an exit code changes without
# a deliberate version bump. Keys are pinned by presence per shape, never by
# position: JSON key order is not API.
RSpec.describe "agent output contract (docs/stability.md)" do
  let(:agent) { Saboteur::Reporter::Agent }

  def provenance
    Saboteur::Reporter::Agent::Provenance.new(
      ref: "origin/main", seed: 7, head: "abc1234", working_tree: "clean", changed_files: 0, mode: "all",
      json_report: ".saboteur/report.json", subjects: [], tests: [], sources: [], config_path: nil,
      digest: nil, cache: true, incremental: false, settings: {}
    )
  end

  def payload_for(report)
    JSON.parse(agent.render(agent.call(report, provenance)))
  end

  def empty_report
    Saboteur::Report.new(results: [], subjects: [], wall_time: 0.1, root: "/tmp", seed: 7)
  end

  def partial_report
    Saboteur::Report.new(results: [], subjects: [person_subject], wall_time: 1,
                         root: File.dirname(person_subject.file), seed: 7,
                         skipped_subjects: { person_subject => "no coverage" })
  end

  # A run the --max-duration budget stopped after confirming a survivor.
  def budget_partial_survivor_report
    Saboteur::Report.new(results: [result_for(:survived)], subjects: [person_subject], wall_time: 1,
                         root: File.dirname(person_subject.file), seed: 7,
                         early_stop: Saboteur::EarlyStop.new(reason: "max_duration",
                                                             unreached: [person_subject.id],
                                                             truncated: [], unverified: []))
  end

  it "pins the payload version" do
    expect(agent::VERSION).to eq(1)
  end

  it "pins the exit codes: the ordinary CLI has 0-4, agent mode is verdict-driven 0-3" do
    expect([agent::EXIT_CLEAN, agent::EXIT_REVIEW, agent::EXIT_INVOCATION, agent::EXIT_INCOMPLETE])
      .to eq([0, 1, 2, 3])
    expect([Saboteur::CLI::EXIT_OK, Saboteur::CLI::EXIT_SURVIVORS, Saboteur::CLI::EXIT_USAGE,
            Saboteur::CLI::EXIT_TOOL, Saboteur::CLI::EXIT_BUDGET]).to eq([0, 1, 2, 3, 4])
  end

  it "pins the run payload's top-level keys by presence, not position" do
    expect(payload_for(empty_report).keys)
      .to contain_exactly("version", "status", "verdict", "exitCode", "provenance", "counts", "score",
                          "scoreDefinition", "killCauses", "incomplete", "timeoutCountedAsDetected", "findings",
                          "warnings", "next")
  end

  it "pins the failure payload's keys" do
    expect(agent.failure("boom", 3).keys)
      .to contain_exactly(:version, :status, :verdict, :exitCode, :message, :next)
  end

  it "pins the truncated last-resort shape to the four guaranteed keys plus the marker" do
    allow(agent).to receive(:render).and_return("x" * (agent::BYTE_BUDGET + 1))
    expect(agent.call(report_of(result_for(:killed)), provenance))
      .to eq(version: 1, status: "complete", verdict: "clean", exitCode: 0, truncated: true)
  end

  # The shape/mode table from docs/stability.md: every documented status,
  # verdict and exit code, in both run and failure shapes.
  {
    "clean run" => [-> { report_of(result_for(:killed)) },   "complete",       "clean",           0],
    "survivors" => [-> { report_of(result_for(:survived)) }, "complete",       "survivors",       1],
    "incomplete run" => [-> { partial_report }, "partial", "incomplete", 3],
    "nothing selected" => [-> { empty_report }, "not_applicable", "not_applicable", 3],
    "budget-stopped with survivors" => [-> { budget_partial_survivor_report }, "partial", "survivors", 1]
  }.each do |name, (build, status, verdict, exit_code)|
    it "maps #{name} to status #{status}, verdict #{verdict}, exit #{exit_code}" do
      expect(payload_for(instance_exec(&build)).values_at("status", "verdict", "exitCode"))
        .to eq([status, verdict, exit_code])
    end
  end

  {
    "usage error" => [2, "invalid_invocation"],
    "tool failure" => [3, "tool_failure"]
  }.each do |name, (exit_code, verdict)|
    it "maps a #{name} to status error, verdict #{verdict}, exit #{exit_code}" do
      expect(agent.failure("boom", exit_code).values_at(:status, :verdict, :exitCode))
        .to eq(["error", verdict, exit_code])
    end
  end

  it "documents every status and verdict value the shapes can emit" do
    run_payloads = [payload_for(report_of(result_for(:killed))), payload_for(partial_report),
                    payload_for(empty_report)]
    failures = [agent.failure("boom", 2), agent.failure("boom", 3)]
    expect(run_payloads.map { |p| p["status"] } | failures.map { |f| f[:status] })
      .to contain_exactly("complete", "partial", "not_applicable", "error")
    expect(run_payloads.map { |p| p["verdict"] } + [payload_for(report_of(result_for(:survived)))["verdict"]] +
           failures.map { |f| f[:verdict] })
      .to contain_exactly("clean", "survivors", "incomplete", "not_applicable", "invalid_invocation",
                          "tool_failure")
  end
end
