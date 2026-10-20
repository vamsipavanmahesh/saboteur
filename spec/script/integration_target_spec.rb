# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
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

  # The runner's hosts may not have a UTF-8 locale: the report reads must
  # not depend on the process default external encoding.
  def lang_c(snippet, *args)
    script = File.expand_path("../../script/integration_target", __dir__)
    Open3.capture3({ "LANG" => "C", "LC_ALL" => "C" }, RbConfig.ruby, "-rjson",
                   "-e", "require #{script.dump}; #{snippet}", *args)
  end

  it "counts a non-ASCII report under LANG=C" do
    report = report_file(mutants("Killed", 2, "note" => "caf\u00E9") + mutants("Survived", 1))
    out, err, status = lang_c("print JSON.generate(IntegrationTarget.counts(ARGV[0]))", report)
    expect(status.exitstatus).to eq(0), err
    expect(JSON.parse(out)).to eq("killed" => 2, "survived" => 1)
  end

  it "accepts then rejects a non-ASCII majority-error report under LANG=C as the allowance tightens" do
    report = report_file(mostly_errored.map { |mutant| mutant.merge("note" => "caf\u00E9") })
    out, err, status = lang_c("print IntegrationTarget.accept_error_majority?(3, 0.6, ARGV[0])", report)
    expect(status.exitstatus).to eq(0), err
    expect(out).to eq("true")
    out, err, status = lang_c("print IntegrationTarget.accept_error_majority?(3, 0.5, ARGV[0])", report)
    expect(status.exitstatus).to eq(0), err
    expect(out).to eq("false")
  end

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

  describe "comparing two runs" do
    def run_report(pairs)
      report_file(pairs.map { |id, status| { "id" => id, "status" => status } }, exit_cause: nil)
    end

    it "reads each mutant's verdict by id" do
      report = run_report("a1" => "Killed", "b2" => "Survived")
      expect(described_class.verdicts(report)).to eq("a1" => "Killed", "b2" => "Survived")
    end

    it "reports no difference for identical verdicts" do
      expect(described_class.verdict_differences({ "a1" => "Killed" }, { "a1" => "Killed" })).to eq([])
    end

    it "reports a changed verdict and a mutant only one run produced" do
      left = { "a1" => "Killed", "b2" => "Survived", "c3" => "Killed" }
      right = { "a1" => "Killed", "b2" => "Killed", "d4" => "Survived" }
      expect(described_class.verdict_differences(left, right))
        .to contain_exactly(%w[b2 Survived Killed], ["c3", "Killed", nil], ["d4", nil, "Survived"])
    end
  end
end
