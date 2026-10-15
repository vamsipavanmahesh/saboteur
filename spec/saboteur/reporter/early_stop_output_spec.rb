# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe "early stop in the reports" do
  def stopped(*ids, results: [result_for(:survived)])
    Saboteur::Report.new(results:, subjects: [person_subject], wall_time: 1.0,
                         root: File.dirname(person_subject.file), seed: 1,
                         early_stop: Saboteur::EarlyStop.new(reason: "fail_fast", unreached: ids))
  end

  def terminal_text(report)
    out = StringIO.new
    Saboteur::Reporter::Terminal.new(out).call(report)
    out.string
  end

  it "puts the early stop in the Stryker JSON, and null when the run was whole" do
    json = Saboteur::Reporter::Stryker.build(stopped("A#x", "B#y"))
    expect(json[:earlyStop]).to eq(reason: "fail_fast", unreachedSubjects: %w[A#x B#y])
    expect(Saboteur::Reporter::Stryker.build(report_of(result_for(:killed)))[:earlyStop]).to be_nil
  end

  it "lists ten unreached subjects without a trailer and eleven with one" do
    ten = terminal_text(stopped(*(1..10).map { |i| "S#{i}#m" }))
    expect(ten.scan("  not run: ").size).to eq(10)
    expect(ten).not_to include("more\n")
    twelve = terminal_text(stopped(*(1..12).map { |i| "S#{i}#m" }))
    expect(twelve.scan("  not run: ").size).to eq(10)
    expect(twelve).to include("  ... 2 more\n")
    expect(terminal_text(stopped(*(1..11).map { |i| "S#{i}#m" }))).to include("  ... 1 more\n")
  end

  it "adds no trailer for a handful of unreached subjects" do
    expect(terminal_text(stopped("A#x", "B#y", "C#z"))).not_to include("more\n")
  end

  it "names --max-duration when the time budget stopped the run (#245)" do
    report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), seed: 1,
                                  early_stop: Saboteur::EarlyStop.new(reason: "max_duration", unreached: ["A#x"]))
    expect(terminal_text(report)).to include("stopped early (--max-duration spent): 1 selected subject did not run")
    json = Saboteur::Reporter::Stryker.build(report)
    expect(json[:earlyStop]).to eq(reason: "max_duration", unreachedSubjects: ["A#x"])
  end

  it "says subject in the singular for one unreached subject" do
    expect(terminal_text(stopped("A#x"))).to include("1 selected subject did not run")
  end

  it "leaves a blank line after the survivor list, and none when nothing survived" do
    with = terminal_text(report_of(result_for(:survived)))
    expect(with).to include("\n\nsaboteur ")
    without = terminal_text(report_of(result_for(:killed)))
    expect(without).not_to include("Survivors")
    expect(without).to start_with("saboteur ")
  end
end
