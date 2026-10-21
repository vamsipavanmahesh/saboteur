# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::Terminal, "early stop and rejected kills" do
  def lines_for(results, **options)
    report = Saboteur::Report.new(results:, subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), seed: 1, **options)
    out = StringIO.new
    described_class.new(out).call(report)
    out.string.lines.map(&:chomp)
  end

  def stop(reason: "fail_fast", unreached: [], truncated: [], unverified: [], planned: nil)
    Saboteur::EarlyStop.new(reason:, unreached:, truncated:, unverified:, planned_mutants: planned)
  end

  it "words a fail-fast stop with every kind of leftover subject, each listed on its own line" do
    early = stop(unreached: %w[A#x B#y], truncated: [{ subject: "C#z", omitted: 3 }, { subject: "D#w", omitted: 2 }],
                 unverified: %w[E#v])
    lines = lines_for([result_for(:killed)], early_stop: early)
    expect(lines).to include(
      "stopped early (--fail-fast): 2 selected subjects did not run; 2 subjects stopped mid-way " \
      "(5 mutants omitted); 1 subject left with unverified results; the score below covers only completed work",
      "  not run: A#x", "  not run: B#y", "  stopped mid-way: C#z (3 mutants omitted)",
      "  stopped mid-way: D#w (2 mutants omitted)", "  unverified: E#v"
    )
  end

  it "uses the singular for one subject and says nothing for an empty kind" do
    lines = lines_for([result_for(:killed)], early_stop: stop(unreached: %w[A#x]))
    expect(lines).to include("stopped early (--fail-fast): 1 selected subject did not run; the score below " \
                             "covers only completed work")
    one_truncated = lines_for([result_for(:killed)], early_stop: stop(truncated: [{ subject: "C#z", omitted: 1 }]))
    expect(one_truncated).to include("stopped early (--fail-fast): 1 subject stopped mid-way (1 mutants omitted); " \
                                     "the score below covers only completed work")
    one_unverified = lines_for([result_for(:killed)], early_stop: stop(unverified: %w[E#v]))
    expect(one_unverified).to include("stopped early (--fail-fast): 1 subject left with unverified results; " \
                                      "the score below covers only completed work")
  end

  it "names the flaky check, not a budget, for unverified verdicts (#1167)" do
    lines = lines_for([result_for(:killed)], early_stop: stop(reason: "unverified", unverified: %w[E#v]))
    expect(lines).to include(
      "unverified verdicts (flaky-check rerun disagreed): 1 subject left with unverified results; the score " \
      "below covers only the verified work",
      "  unverified: E#v"
    )
    expect(lines.grep(/max-duration/)).to be_empty
  end

  it "names the budget for a max-duration stop and caps each list at ten" do
    many = Array.new(11) { |index| "S#{index}#m" }
    lines = lines_for([result_for(:killed)], early_stop: stop(reason: "max_duration", unreached: many, planned: 5))
    expect(lines).to include(
      "stopped early (--max-duration spent): 11 selected subjects did not run; the score below " \
      "covers only completed work",
      "  not run: S9#m", "  ... 1 more"
    )
    expect(lines).not_to include("  not run: S10#m")
  end

  it "prints no more-line when a list holds exactly ten" do
    ten = Array.new(10) { |index| "S#{index}#m" }
    lines = lines_for([result_for(:killed)], early_stop: stop(unverified: ten))
    expect(lines).to include("  unverified: S9#m")
    expect(lines.grep(/\A  \.\.\. \d+ more\z/)).to be_empty
  end

  it "prints no stop line when the run did not stop early" do
    expect(lines_for([result_for(:killed)]).grep(/stopped early/)).to be_empty
  end

  it "lists rejected kills under their own heading, apart from errors" do
    rejected = result_for(:error, reason: "tests also fail unchanged", rejected_kill: true)
    lines = lines_for([rejected])
    expect(lines).to include(
      "Rejected kills (tests also fail with the method unchanged; not counted as killed):",
      "  Person#adult? comparison #{rejected.digest}: tests also fail unchanged"
    )
    expect(lines).not_to include("Errors (not counted as killed):")
  end

  it "lists real errors under the errors heading and no rejected-kills heading" do
    errored = result_for(:error, reason: "boom")
    lines = lines_for([errored])
    expect(lines).to include("Errors (not counted as killed):", "  Person#adult? comparison #{errored.digest}: boom")
    expect(lines.grep(/\ARejected kills/)).to be_empty
  end

  it "says how many kills the unchanged-method check rejected" do
    rejected = result_for(:error, reason: "x", rejected_kill: true)
    out = StringIO.new
    report = Saboteur::Report.new(results: [rejected, result_for(:killed)], subjects: [person_subject],
                                  wall_time: 1.0, root: File.dirname(person_subject.file), seed: 1)
    described_class.new(out, verbose: true).call(report)
    expect(out.string.lines.map(&:chomp)).to include("kills rejected by unchanged-method check: 1")
  end

  it "warns about a --test-command run that never exercised a subject" do
    lines = lines_for([result_for(:survived)], test_command: "bin/test")
    expect(lines).to include("Person#adult?: no coverage map under --test-command; check your command exercises " \
                             "person.rb")
    expect(lines_for([result_for(:survived)]).grep(/no coverage map/)).to be_empty
  end

  it "counts rejected kills in the closing summary line, with a plural only for more than one" do
    one = result_for(:error, reason: "x", rejected_kill: true)
    two = result_for(:error, replacement: "<", reason: "x", rejected_kill: true)
    expect(lines_for([one])).to include(a_string_including("1 error (1 rejected kill)"))
    expect(lines_for([one, two])).to include(a_string_including("2 errors (2 rejected kills)"))
    expect(lines_for([result_for(:killed)])).not_to include(a_string_including("error"))
  end

  it "leaves a blank line after the survivors only when there are some" do
    survived = lines_for([result_for(:survived)])
    header = survived.index { |line| line.start_with?("saboteur ") }
    expect(survived[header - 1]).to eq("")
    expect(lines_for([result_for(:killed)]).first).to start_with("saboteur ")
  end

  it "prints no inline suppression heading when there are none" do
    expect(lines_for([result_for(:killed)]).grep(/Inline suppressions/)).to be_empty
  end

  it "prints no more-line when the lists are short, and pluralises two unverified subjects" do
    lines = lines_for([result_for(:killed)], early_stop: stop(unverified: %w[E#v F#w]))
    expect(lines.grep(/more\z/)).to be_empty
    expect(lines).to include(a_string_including("2 subjects left with unverified results"))
  end

  it "warns only for a subject with survivors and no kills, timeouts or errors" do
    warning = "Person#adult?: no coverage map under --test-command; check your command exercises person.rb"
    killed = result_for(:killed, replacement: "<")
    errored = result_for(:error, replacement: "<=", reason: "x")
    expect(lines_for([result_for(:survived), killed], test_command: "t")).not_to include(warning)
    expect(lines_for([result_for(:survived), result_for(:timeout, replacement: "<")], test_command: "t"))
      .not_to include(warning)
    expect(lines_for([result_for(:survived), errored], test_command: "t")).not_to include(warning)
    expect(lines_for([result_for(:skipped, reason: "r")], test_command: "t")).not_to include(warning)
  end

  it "prints the first result's hint even when a later result has none" do
    first = result_for(:unreachable, reason: "first reason")
    second = result_for(:unreachable, replacement: "<")
    expect(lines_for([first, second])).to include("  hint: first reason")
  end

  it "prints the hint of the first out-of-score result, not the last" do
    first = result_for(:unreachable, reason: "first reason")
    second = result_for(:unreachable, replacement: "<", reason: "second reason")
    lines = lines_for([first, second])
    expect(lines).to include("  hint: first reason")
    expect(lines).not_to include("  hint: second reason")
  end
end
