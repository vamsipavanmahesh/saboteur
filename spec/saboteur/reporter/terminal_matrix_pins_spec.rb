# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::Terminal, "matrix, whole-body and error pins" do
  let(:out) { StringIO.new }

  def render(report, **options)
    described_class.new(out, **options).call(report)
    out.string
  end

  def report_with(*results, **extra)
    Saboteur::Report.new(results: results, subjects: [person_subject], wall_time: 1.25,
                         root: File.dirname(person_subject.file), seed: 1, **extra)
  end

  def matrix_report(*results)
    Saboteur::Report.new(results: results, subjects: [person_subject], wall_time: 1.0,
                         root: File.dirname(person_subject.file), seed: 1, matrix: true)
  end

  it "names the blind list and prints each test line exactly, capped at the listing limit" do
    many = Array.new(22) { |index| "t#{format('%02d', index)}" }
    text = render(matrix_report(result_for(:survived, covered_by: many, executed: many)))
    expect(text).to include("\n  blind (covered mutants, killed none): 22\n    t00  1 covered\n",
                            "    t19  1 covered\n    ... 2 more\n")
    expect(text).not_to include("t20")
  end

  it "prints the redundant list line with the kill count" do
    killed = result_for(:killed, killed_by: %w[a b], covered_by: %w[a b], executed: %w[a b])
    expect(render(matrix_report(killed))).to include(
      "\n  redundant (every kill had another killer): 2\n    a  1 kills\n"
    )
  end

  it "prints the incomplete note as one exact line" do
    stopped = result_for(:killed, killed_by: %w[a], covered_by: %w[a b], executed: %w[a])
    expect(render(matrix_report(stopped))).to include(
      "\n  1 mutants stopped before every covering test ran (incomplete): " \
      "their tests get no blind or redundant verdict\n"
    )
  end

  it "prints no whole-body line when the run has only whole-body mutants" do
    text = render(report_with(result_for(:killed, coarse: true, kill_cause: "assertion")), verbose: true)
    expect(text).not_to include("without whole-body mutants")
  end

  it "prints no whole-body line when the run has no whole-body mutants" do
    text = render(report_with(result_for(:killed, kill_cause: "assertion")), verbose: true)
    expect(text).not_to include("without whole-body mutants")
  end

  it "prints the whole-body line when both kinds ran" do
    text = render(report_with(result_for(:killed, coarse: true, kill_cause: "assertion"),
                              result_for(:killed, replacement: "<", kill_cause: "assertion")), verbose: true)
    expect(text).to include("score without whole-body mutants 100.0 %")
  end

  it "prints no more-line when fewer errors than the cap occurred" do
    text = render(report_with(result_for(:killed), result_for(:error, reason: "boom"),
                              result_for(:error, reason: "bang", replacement: "<")))
    expect(text).to include("Errors (not counted as killed):")
    expect(text).not_to include("more")
  end

  it "joins several excluded operators with a comma and a space" do
    policy = Saboteur::Config.new({ "exclude_operators" => %w[range comparison] }).operator_policy
    text = render(report_with(result_for(:killed), operator_policy: policy))
    expect(text).to include("Excluded operators: #{policy['excluded'].join(', ')} (policy ")
    expect(policy["excluded"].size).to be > 1
  end

  it "prints no excluded-operators line when the policy excludes nothing" do
    policy = Saboteur::Config.new({}).operator_policy
    expect(policy["excluded"]).to be_empty
    expect(render(report_with(result_for(:killed), operator_policy: policy))).not_to include("Excluded operators")
  end

  it "prints no crash-by-operator line when every kill was a failed assertion" do
    text = render(report_with(result_for(:killed, kill_cause: "assertion")), verbose: true)
    expect(text).to include("kills: 1 by a failed assertion, 0 by a crash")
    expect(text).not_to include("crash kills by operator")
  end

  it "leaves out an operator that has no crash kills" do
    crash = result_for(:killed, kill_cause: "TypeError")
    plain = result_for(:killed, kill_cause: "assertion", replacement: "x", operator: "range")
    text = render(report_with(crash, plain), verbose: true)
    expect(text).to include("crash kills by operator: comparison 1 of 1\n")
  end
end
