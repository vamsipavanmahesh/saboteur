# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::Terminal do
  let(:out) { StringIO.new }

  def render(report)
    described_class.new(out).call(report)
    out.string
  end

  it "prints counts, score, timing and a diff per survivor" do
    text = render(report_of(result_for(:killed, runtime: 0.5), result_for(:survived, runtime: 0.5)))
    expect(text).to include(
      "1 subjects, 2 mutants, wall 1.25 s",
      "killed 1  survived 1  timeout 0  error 0  skipped 0",
      "score 50.0 %",
      "mean time per executed mutant 0.500 s",
      "Person#adult? comparison",
      "person.rb:2",
      "-  def adult?; @age >= 18; end\n+  def adult?; @age > 18; end"
    )
  end

  it "lists errors separately and does not call them killed" do
    text = render(report_of(result_for(:error, reason: "child killed by signal 9 during tests")))
    expect(text).to include("killed 0", "error 1", "Errors (not counted as killed):", "signal 9")
  end

  it "shows skip reasons, warnings and ignored survivors" do
    survivor = result_for(:survived)
    survivor.ignored = "equivalent: ages are integers"
    text = render(report_of(survivor, result_for(:skipped, reason: "no coverage"), warnings: ["stale entry"]))
    expect(text).to include("survived 1 (1 ignored)", "skipped: no coverage: 1", "warning: stale entry",
                            "ignored: equivalent: ages are integers")
  end

  it "splits kills into assertion kills and crash kills, by operator" do
    text = render(report_of(result_for(:killed, kill_cause: "assertion"),
                            result_for(:killed, replacement: "<", kill_cause: "NoMethodError"),
                            result_for(:killed, replacement: "<=", kill_cause: "NoMethodError")))
    expect(text).to include("kills: 1 by a failed assertion, 2 by a crash (NoMethodError 2)",
                            "crash kills by operator: comparison 2 of 3")
  end

  it "shows one survivor per line in review mode, and says how many more the JSON holds" do
    survivors = [result_for(:survived, replacement: ">"), result_for(:survived, replacement: "<=")]
    report = Saboteur::Report.new(results: survivors, subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), review: true)
    text = render(report)
    expect(text.scan("Person#adult? comparison").size).to eq(1)
    expect(text).to include("1 more survivor on this line in the JSON report")
  end

  it "never lets an ignored survivor hide a live one on the same line in review mode" do
    ignored = result_for(:survived, replacement: ">")
    ignored.ignored = "equivalent"
    live = result_for(:survived, replacement: "<=")
    report = Saboteur::Report.new(results: [ignored, live], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), review: true)
    expect(render(report)).to include("+  def adult?; @age <= 18; end")
  end

  it "prints n/a for the score when nothing ran" do
    expect(render(report_of)).to include("score n/a")
  end
end
