# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The saboteur.complete flag (#246): true only when the run judged everything
# it selected, so a consumer can tell a fixed survivor from a dropped one.
RSpec.describe Saboteur::Reporter::Agent::Incomplete, ".complete?" do
  def complete_in_json(report)
    Saboteur::Reporter::Stryker.build(report).dig(:saboteur, :complete)
  end

  # Every code Incomplete.reasons can emit, with the benign ones apart.
  blocking = %w[shard no_coverage unsupported ran_at_load preloaded unreachable mutant_cap errors resource_limit
                unverified invalid_file_syntax unreadable fail_fast max_duration fail_fast_truncated
                max_duration_truncated]

  blocking.each do |code|
    it "is false for #{code}" do
      allow(described_class).to receive(:reasons).and_return([{ reason: code, count: 1, meaning: "x" }])

      expect(described_class.complete?(report_of(result_for(:killed)))).to be(false)
    end
  end

  it "is false when a blocking reason sits among benign ones" do
    allow(described_class).to receive(:reasons)
      .and_return([{ reason: "inline_suppressed", count: 2, meaning: "x" },
                   { reason: "errors", count: 1, meaning: "y" }])

    expect(described_class.complete?(report_of(result_for(:killed)))).to be(false)
  end

  it "is true with no reasons, and with inline suppression only" do
    expect(described_class.complete?(report_of(result_for(:survived)))).to be(true)
    allow(described_class).to receive(:reasons).and_return([{ reason: "inline_suppressed", count: 2, meaning: "x" }])
    expect(described_class.complete?(report_of(result_for(:survived)))).to be(true)
  end

  it "reads the real signals: an errored mutant and an early stop make the JSON report incomplete" do
    expect(complete_in_json(report_of(result_for(:survived)))).to be(true)
    expect(complete_in_json(report_of(result_for(:killed), result_for(:error, replacement: "<")))).to be(false)
    stop = Saboteur::EarlyStop.new(reason: "max_duration", unreached: %w[A#x], truncated: [], unverified: [])
    report = Saboteur::Report.new(results: [result_for(:survived)], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), seed: 1, early_stop: stop)
    expect(complete_in_json(report)).to be(false)
  end

  it "reads syntax and unreadable discovery failures" do
    failure = Struct.new(:reason)
    %w[invalid_file_syntax unreadable].each do |reason|
      report = Saboteur::Report.new(results: [result_for(:survived)], subjects: [person_subject], wall_time: 1.0,
                                    root: File.dirname(person_subject.file), seed: 1,
                                    discovery_failures: [failure.new(reason)])
      expect(complete_in_json(report)).to be(false)
    end
  end
end
