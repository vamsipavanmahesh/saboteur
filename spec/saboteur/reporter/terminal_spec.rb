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

RSpec.describe Saboteur::Reporter::Terminal, "details" do
  def render(report)
    StringIO.new.tap { |out| described_class.new(out).call(report) }.string
  end

  # A mutant of the person fixture's body, at the given text.
  def mutant(status, at:, replacement:, operator: "test", coarse: false, **)
    source = person_subject.file_source
    start = source.index(at)
    edit = Saboteur::MutationSource::Edit.new(file: person_subject.file, start_byte: start,
                                              end_byte: start + at.bytesize, replacement:)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: person_subject.id, operator:, edits: [edit],
                                                      coarse:)
    Saboteur::MutantResult.new(subject: person_subject, mutation:, status:,
                               mutated_source: person_subject.apply(mutation.edits), **)
  end

  def review(*results)
    Saboteur::Report.new(results:, subjects: [person_subject], wall_time: 1.0,
                         root: File.dirname(person_subject.file), review: true)
  end

  it "reports invalid mutations and reused verdicts only when there are some" do
    quiet = render(report_of(result_for(:killed)))
    expect(quiet).not_to include("invalid mutations", "reused")
    report = Saboteur::Report.new(results: [result_for(:killed, reused: true)], subjects: [person_subject],
                                  wall_time: 1.0, root: File.dirname(person_subject.file), invalid_mutations: 2)
    expect(render(report)).to include("invalid mutations dropped (did not parse): 2",
                                      "reused 1 of 1 verdicts from earlier runs")
  end

  it "prints no kill line without kills, and no crash lines without crashes" do
    expect(render(report_of(result_for(:survived)))).not_to include("kills:")
    text = render(report_of(result_for(:killed, kill_cause: "assertion")))
    expect(text).to include("kills: 1 by a failed assertion, 0 by a crash\n")
    expect(text).not_to include("crash kills by operator")
  end

  it "lists only operators that crash-killed" do
    text = render(report_of(result_for(:killed, kill_cause: "TypeError"),
                            mutant(:killed, at: "@age", replacement: "1", operator: "other", kill_cause: "assertion")))
    expect(text).to include("crash kills by operator: comparison 1 of 1\n")
  end

  it "lists at most ten errors and counts the rest" do
    errors = Array.new(12) { |n| result_for(:error, replacement: "x#{n}", reason: "boom #{n}") }
    text = render(report_of(*errors))
    expect(text.scan(/: boom \d+$/).size).to eq(10)
    expect(text).to include("  ... 2 more\n")
    expect(render(report_of(*errors.first(10)))).not_to include("more\n")
  end

  it "prints the survivors section only when there are survivors" do
    expect(render(report_of(result_for(:killed)))).not_to include("Survivors:")
    expect(render(report_of(result_for(:survived)))).to include("\nSurvivors:\n")
  end

  it "says survivor or survivors depending on how many more share the line" do
    two = render(review(result_for(:survived), result_for(:survived, replacement: "<=")))
    three = render(review(result_for(:survived), result_for(:survived, replacement: "<="),
                          result_for(:survived, replacement: "==")))
    expect(two).to include("1 more survivor on this line")
    expect(three).to include("2 more survivors on this line")
  end

  it "shows every survivor, with no 'more' note, outside review mode" do
    text = render(report_of(result_for(:survived), result_for(:survived, replacement: "<=")))
    expect(text.scan("Person#adult? comparison").size).to eq(2)
    expect(text).not_to include("more survivor")
  end

  it "prefers a coarse survivor over a fine one that starts at the same byte" do
    fine = mutant(:survived, at: "@age >= 18", replacement: "nil", operator: "statement_removal")
    coarse = mutant(:survived, at: "@age >= 18", replacement: "nil", operator: "body_nil", coarse: true)
    expect(render(review(fine, coarse))).to include("Person#adult? body_nil")
  end

  it "prints no errors section and no ignored note when there is nothing to say" do
    text = render(report_of(result_for(:survived)))
    expect(text).not_to include("Errors", "ignored:")
  end

  it "keeps survivors on different lines apart in review mode" do
    subject = subjects_in("class Two\n  def m(a)\n    b = a + 1\n    b * 2\n  end\nend\n").first
    results = ["+", "*"].map do |operator|
      at = subject.file_source.index(" #{operator} ") + 1
      edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 1,
                                                replacement: operator == "+" ? "-" : "/")
      mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "arithmetic", edits: [edit])
      Saboteur::MutantResult.new(subject:, mutation:, status: :survived, mutated_source: subject.apply([edit]))
    end
    report = Saboteur::Report.new(results:, subjects: [subject], wall_time: 1.0,
                                  root: File.dirname(subject.file), review: true)
    expect(render(report).scan("Two#m arithmetic").size).to eq(2)
  end
end
