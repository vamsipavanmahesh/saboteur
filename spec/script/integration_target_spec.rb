# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../../script/integration_target"

RSpec.describe IntegrationTarget do
  def report_file(mutants, exit_cause: "errorMajority")
    document = { "files" => { "a.rb" => { "mutants" => mutants } } }
    document["saboteur"] = { "exitCause" => exit_cause } if exit_cause
    File.join(Dir.mktmpdir, "report.json").tap { |path| File.write(path, JSON.generate(document)) }
  end

  def mutants(status, count, **extra)
    Array.new(count) { { "status" => status, **extra } }
  end

  let(:mostly_errored) { mutants("Killed", 70) + mutants("RuntimeError", 77) }

  it "accepts exit 3 when the fresh report shows the majority-error outcome within the allowance" do
    expect(described_class.accept_error_majority?(3, 0.6, report_file(mostly_errored))).to be(true)
  end

  it "rejects any other exit code, including the ordinary failures" do
    expect(described_class.accept_error_majority?(1, 0.6, report_file(mostly_errored))).to be(false)
    expect(described_class.accept_error_majority?(2, 0.6, report_file(mostly_errored))).to be(false)
  end

  it "rejects exit 3 for a target without an allowance" do
    expect(described_class.accept_error_majority?(3, nil, report_file(mostly_errored))).to be(false)
  end

  it "rejects an errored fraction beyond the allowance" do
    expect(described_class.accept_error_majority?(3, 0.4, report_file(mostly_errored))).to be(false)
  end

  it "rejects an errored fraction that is not a majority: exit 3 had another cause" do
    report = mutants("Killed", 140) + mutants("RuntimeError", 7)
    expect(described_class.accept_error_majority?(3, 0.6, report_file(report))).to be(false)
  end

  it "rejects a report without the CLI's errorMajority marker" do
    expect(described_class.accept_error_majority?(3, 0.6, report_file(mostly_errored, exit_cause: nil))).to be(false)
  end

  it "rejects a report whose exit cause is the incomplete run, not the error majority" do
    report = described_class.accept_error_majority?(3, 0.6,
                                                    report_file(mostly_errored, exit_cause: "incompleteUnderThreshold"))
    expect(report).to be(false)
  end

  it "rejects a run with resource-limited mutants: a sick machine, not a known error profile" do
    report = mutants("Killed", 70) + mutants("RuntimeError", 76) +
             mutants("RuntimeError", 1, "statusReason" => "resource limit: memory cap")
    expect(described_class.accept_error_majority?(3, 0.6, report_file(report))).to be(false)
  end

  it "rejects a missing report" do
    expect(described_class.accept_error_majority?(3, 0.6, File.join(Dir.mktmpdir, "missing.json"))).to be(false)
  end

  it "rejects a report that is not JSON" do
    path = File.join(Dir.mktmpdir, "report.json")
    File.write(path, "not json")
    expect(described_class.accept_error_majority?(3, 0.6, path)).to be(false)
  end
end
