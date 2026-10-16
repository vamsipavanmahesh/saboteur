# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe "early stop in the reports" do
  def stopped(*ids, results: [result_for(:survived)])
    Saboteur::Report.new(results:, subjects: [person_subject], wall_time: 1.0,
                         root: File.dirname(person_subject.file), seed: 1,
                         early_stop: Saboteur::EarlyStop.new(reason: "fail_fast", unreached: ids, truncated: [],
                                                             unverified: []))
  end

  def terminal_text(report)
    out = StringIO.new
    Saboteur::Reporter::Terminal.new(out).call(report)
    out.string
  end

  it "puts the early stop in the Stryker JSON, and null when the run was whole" do
    json = Saboteur::Reporter::Stryker.build(stopped("A#x", "B#y"))
    expect(json[:earlyStop]).to eq(reason: "fail_fast", unreachedSubjects: %w[A#x B#y], truncatedSubjects: [],
                                   unverifiedSubjects: [])
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

  # Singular already covered above: plurals decide the 's', and each kind
  # appears only when its own list is non-empty (#296).
  it "summarizes two unreached, two truncated and two unverified subjects in the plural (#296)" do
    stop = Saboteur::EarlyStop.new(reason: "max_duration", unreached: ["A#x", "B#y"],
                                   truncated: [{ subject: "C#z", omitted: 2 }, { subject: "D#w", omitted: 1 }],
                                   unverified: ["E#u", "F#v"])
    report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), seed: 1, early_stop: stop)
    text = terminal_text(report)
    expect(text).to include("2 selected subjects did not run")
    expect(text).to include("2 subjects stopped mid-way (3 mutants omitted)")
    expect(text).to include("2 subjects left with unverified results")
  end

  it "mentions only the kinds that actually happened (#296)" do
    stop = Saboteur::EarlyStop.new(reason: "max_duration", unreached: ["A#x", "B#y"], truncated: [], unverified: [])
    report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), seed: 1, early_stop: stop)
    text = terminal_text(report)
    expect(text).to include("2 selected subjects did not run")
    expect(text).not_to include("stopped mid-way")
    expect(text).not_to include("unverified results")
  end

  it "adds no trailer for a handful of unreached subjects" do
    expect(terminal_text(stopped("A#x", "B#y", "C#z"))).not_to include("more\n")
  end

  it "names --max-duration when the time budget stopped the run (#245)" do
    report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), seed: 1,
                                  early_stop: Saboteur::EarlyStop.new(reason: "max_duration", unreached: ["A#x"],
                                                                      truncated: [], unverified: []))
    expect(terminal_text(report)).to include("stopped early (--max-duration spent): 1 selected subject did not run")
    json = Saboteur::Reporter::Stryker.build(report)
    expect(json[:earlyStop]).to eq(reason: "max_duration", unreachedSubjects: ["A#x"], truncatedSubjects: [],
                                   unverifiedSubjects: [])
  end

  it "reports subjects the budget stopped mid-way with their omitted mutants (#245)" do
    report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), seed: 1,
                                  early_stop: Saboteur::EarlyStop.new(reason: "max_duration", unreached: [],
                                                                      truncated: [{ subject: "A#x", omitted: 2 }],
                                                                      unverified: []))
    expect(terminal_text(report))
      .to include("stopped early (--max-duration spent): 1 subject stopped mid-way (2 mutants omitted)")
    json = Saboteur::Reporter::Stryker.build(report)
    expect(json[:earlyStop]).to eq(reason: "max_duration", unreachedSubjects: [],
                                   truncatedSubjects: [{ subject: "A#x", omittedMutants: 2 }],
                                   unverifiedSubjects: [])
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

RSpec.describe "early stop detail lines (#296)" do
  def stopped_report(unreached: [], truncated: [], unverified: [])
    Saboteur::Report.new(results: [result_for(:survived)], subjects: [person_subject], wall_time: 1.0,
                         root: File.dirname(person_subject.file), seed: 1,
                         early_stop: Saboteur::EarlyStop.new(reason: "max_duration", unreached: unreached,
                                                             truncated: truncated, unverified: unverified))
  end

  def terminal_text(report)
    out = StringIO.new
    Saboteur::Reporter::Terminal.new(out).call(report)
    out.string
  end

  it "prints the full summary, the per-subject lines and the trailer, exactly" do
    report = stopped_report(unreached: ["A#x"],
                            truncated: [{ subject: "B#y", omitted: 2 }],
                            unverified: ["C#z"])
    text = terminal_text(report)
    expect(text).to include("stopped early (--max-duration spent): 1 selected subject did not run; " \
                            "1 subject stopped mid-way (2 mutants omitted); 1 subject left with unverified results; " \
                            "the score below covers only completed work")
    expect(text).to include("  not run: A#x")
    expect(text).to include("  stopped mid-way: B#y (2 mutants omitted)")
    expect(text).to include("  unverified: C#z")
  end

  it "pluralizes the summary parts and joins them with semicolons" do
    report = stopped_report(unreached: %w[A#x B#y], truncated: [{ subject: "C#z", omitted: 3 }])
    expect(terminal_text(report)).to include("2 selected subjects did not run; 1 subject stopped mid-way " \
                                             "(3 mutants omitted);")
  end

  it "truncates each listing after ten entries with a remainder line" do
    truncated = (1..12).map { |i| { subject: "T#{i}#m", omitted: 1 } }
    unverified = (1..11).map { |i| "U#{i}#m" }
    text = terminal_text(stopped_report(truncated: truncated, unverified: unverified))
    expect(text.scan("  stopped mid-way: ").size).to eq(10)
    expect(text).to include("  ... 2 more")
    expect(text.scan("  unverified: ").size).to eq(10)
    expect(text).to include("  ... 1 more")
  end
end
