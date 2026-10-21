# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::Terminal, "pins" do
  let(:out) { StringIO.new }

  def render(report, **options)
    described_class.new(out, **options).call(report)
    out.string
  end

  def report_with(*results, **extra)
    Saboteur::Report.new(results: results, subjects: [person_subject], wall_time: 1.25,
                         root: File.dirname(person_subject.file), seed: 1, **extra)
  end

  it "lists inline suppressions with their file, line, subject, operator, digest and reason" do
    entry = { file: File.join(File.dirname(person_subject.file), "lib/a.rb"), line: 4, subject: "A#b",
              operator: "comparison", digest: "abcd1234abcd1234", reason: "equivalent" }
    text = render(report_with(result_for(:killed), inline_suppressions: [entry]))
    expect(text).to include("Inline suppressions: 1 (outside the score)\n",
                            "  lib/a.rb:4 A#b comparison abcd1234abcd1234: equivalent\n")
  end

  it "prints no inline suppression heading when there are none" do
    expect(render(report_with(result_for(:killed)))).not_to include("Inline suppressions")
  end

  it "says how many mutants were not run when the duration budget stopped the run" do
    stop = Saboteur::EarlyStop.new(reason: "max_duration", unreached: ["Other#x"], truncated: [], unverified: [],
                                   planned_mutants: 57)
    results = [result_for(:killed), result_for(:survived), result_for(:killed), result_for(:survived)]
    expect(render(report_with(*results, early_stop: stop))).to include("partial: 53 of 57 mutants not run\n")
  end

  it "says the mutant count is unknown when planning never finished" do
    stop = Saboteur::EarlyStop.new(reason: "max_duration", unreached: ["Other#x"], truncated: [], unverified: [])
    expect(render(report_with(result_for(:killed), early_stop: stop)))
      .to include("partial: mutant count unknown; the budget was spent before planning finished\n")
  end

  it "names the excluded operators and how many are enabled" do
    policy = Saboteur::Config.new({ "exclude_operators" => ["range"] }).operator_policy
    text = render(report_with(result_for(:killed), operator_policy: policy))
    expect(text).to include("Excluded operators: range (policy #{policy['version']}; #{policy['effective'].size} " \
                            "enabled)\n")
  end

  it "explains hazardous mutations that were suppressed" do
    text = render(report_with(result_for(:killed), hazard_suppressions: 3))
    expect(text).to include("hazardous mutations suppressed: 3 (--allow-hazardous runs them anyway; " \
                            "the canary still watches the tree)\n")
  end

  it "lists skipped subjects with their file, line and reason" do
    root = File.dirname(person_subject.file)
    text = render(report_with(result_for(:killed), skipped_subjects: { person_subject => "no coverage" }))
    expect(text).to include("methods never run by tests: 1\n",
                            "  #{person_subject.id} #{person_subject.file.delete_prefix("#{root}/")}:" \
                            "#{person_subject.start_line}: no coverage\n")
  end

  describe "kill causes" do
    let(:killed) do
      [result_for(:killed, kill_cause: "TypeError"), result_for(:killed, kill_cause: "NoMethodError", replacement: "<"),
       result_for(:killed, kill_cause: "NoMethodError", replacement: "<=")]
    end

    it "lists crash classes by how often they killed, most first, separated by commas" do
      expect(render(report_with(*killed), verbose: true))
        .to include("kills: 0 by a failed assertion, 3 by a crash (NoMethodError 2, TypeError 1)\n")
    end

    it "lists the operators that kill by crashing, separated by commas" do
      other = result_for(:killed, kill_cause: "TypeError", replacement: "x", operator: "range")
      text = render(report_with(*killed, other), verbose: true)
      expect(text).to include("crash kills by operator: comparison 3 of 3, range 1 of 1\n")
    end
  end
end
