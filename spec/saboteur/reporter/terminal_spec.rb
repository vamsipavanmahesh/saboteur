# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::Terminal do
  let(:out) { StringIO.new }

  def render(report, **options)
    described_class.new(out, **options).call(report)
    out.string
  end

  def verbose_render(report)
    render(report, verbose: true)
  end

  it "prints counts, score, timing and a diff per survivor" do
    text = render(report_of(result_for(:killed, runtime: 0.5), result_for(:survived, runtime: 0.5)),
                  verbose: true)
    expect(text).to include(
      "1 subjects, 2 mutants, wall 1.25 s, seed 1 (repeat with --seed 1)",
      "killed 1  survived 1  timeout 0  resource limit 0  error 0  skipped 0",
      "score 50.0 %",
      "mean time per executed mutant 0.500 s",
      "person.rb:2 in Person#adult?",
      "- comparison >= -> > "
    )
  end

  it "prints excluded operators, and only when the policy excludes some" do
    excluded = Saboteur::Config.new({ "exclude_operators" => %w[condition_negation range] }).operator_policy
    text = render(report_of(result_for(:killed), policy: excluded))
    expect(text).to include("Excluded operators: condition_negation, range (policy #{excluded['version']}; ")
    out.truncate(0)
    out.rewind
    expect(render(report_of(result_for(:killed)))).not_to include("Excluded operators")
    out.truncate(0)
    out.rewind
    plain = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.0,
                                 root: File.dirname(person_subject.file), seed: 1)
    expect(render(plain)).not_to include("Excluded operators")
  end

  it "prints the test matrix before the summary only for a --matrix run, capped" do
    killed = result_for(:killed, killed_by: %w[a b], covered_by: %w[a b], executed: %w[a b])
    plain = report_of(killed)
    expect(render(plain)).not_to include("test matrix")
    out.truncate(0)
    out.rewind

    matrix = Saboteur::Report.new(results: [killed], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), seed: 1, matrix: true)
    text = render(matrix)
    expect(text).to include("test matrix: 2 tests ran against mutants", "blind (covered mutants, killed none): 0",
                            "redundant (every kill had another killer): 2", "    a  1 kills", "    b  1 kills")
    expect(text.index("test matrix")).to be < text.index("saboteur #{Saboteur::VERSION}:")

    many = Array.new(22) { |index| "t#{format('%02d', index)}" }
    survivor = result_for(:survived, covered_by: many, executed: many)
    blind = Saboteur::Report.new(results: [survivor], subjects: [person_subject],
                                 wall_time: 1.0, root: File.dirname(person_subject.file), seed: 1, matrix: true)
    out.truncate(0)
    out.rewind
    twenty = result_for(:survived, covered_by: many.first(20), executed: many.first(20))
    exactly = Saboteur::Report.new(results: [twenty],
                                   subjects: [person_subject], wall_time: 1.0,
                                   root: File.dirname(person_subject.file), seed: 1, matrix: true)
    text = render(exactly)
    expect(text).to include("    t19  1 covered")
    expect(text[text.index("test matrix")..]).not_to match(/\.\.\. \d+ more/)
    out.truncate(0)
    out.rewind
    expect(render(blind)).to include("blind (covered mutants, killed none): 22", "    t19  1 covered", "... 2 more")
  end

  it "says how many mutants stopped before every covering test ran, and only then" do
    stopped = result_for(:killed, killed_by: %w[a], covered_by: %w[a b], executed: %w[a])
    whole = result_for(:killed, killed_by: %w[a], covered_by: %w[a], replacement: "<=", executed: %w[a])
    root = File.dirname(person_subject.file)
    partial = Saboteur::Report.new(results: [stopped], subjects: [person_subject], wall_time: 1.0, root:, seed: 1,
                                   matrix: true)
    expect(render(partial)).to include("1 mutants stopped before every covering test ran (incomplete)")
    out.truncate(0)
    out.rewind
    complete = Saboteur::Report.new(results: [whole], subjects: [person_subject], wall_time: 1.0, root:, seed: 1,
                                    matrix: true)
    expect(render(complete)).not_to include("stopped before every covering test ran")
  end

  it "ends a run with survivors on the next steps, after the legend, and a clean run without them" do
    text = render(report_of(result_for(:killed), result_for(:survived)))
    expect(text.index("legend:")).to be < text.index("Next steps:")
  end

  it "leaves the next steps out of a clean run" do
    expect(render(report_of(result_for(:killed)))).not_to include("Next steps:")
  end

  it "prints survivors before the summary, and keeps debug statistics out of the default report" do
    text = render(report_of(result_for(:killed, runtime: 0.5), result_for(:survived, runtime: 0.5)))
    expect(text.index("Survivors (1):")).to be < text.index("saboteur ")
    expect(text).not_to include("mean time per executed mutant", "kills rejected", "(killed+timeout)/")
  end

  it "prints the survivor's source line and a hint once per line, with one compact line per mutation" do
    text = render(report_of(result_for(:survived), result_for(:survived, replacement: "<=")))
    expect(text.scan("      2: def adult?; @age >= 18; end").size).to eq(1)
    expect(text).to include("- comparison >= -> > ", "- comparison >= -> <= ", "hint: try an example at the boundary",
                            "Hints are suggestions, not diagnoses")
  end

  it "words the timeout legend as an exceeded deadline, not a hang" do
    text = render(report_of(result_for(:timeout)))
    expect(text).to include("timeout: exceeded its deadline")
    expect(text).not_to include("hung")
  end

  it "does not diagnose a missing example or assertion in any hint" do
    hints = Saboteur::Reporter::SurvivorHints::BY_OPERATOR.values + [Saboteur::Reporter::SurvivorHints::COARSE]
    expect(hints).to all(start_with("try "))
    expect(hints.join(" ")).not_to match(/\bno (example|assertion|test)\b/)
  end

  it "prints the hint caveat only when a hint was shown" do
    expect(render(report_of(result_for(:killed)))).not_to include("Hints are suggestions")
    ignored = result_for(:survived).tap { |result| result.ignored = "equivalent" }
    expect(render(report_of(ignored))).not_to include("Hints are suggestions")
  end

  it "keeps each same-line mutant's own covering tests, reuse and order" do
    a = result_for(:survived, replacement: ">", covered_by: ["./spec/a_spec.rb[1:1]", "./spec/a_spec.rb[1:2]"])
    b = result_for(:survived, replacement: "<=", covered_by: ["./spec/a_spec.rb[1:2]", "./spec/a_spec.rb[1:1]"])
    c = result_for(:survived, replacement: "==", covered_by: ["./spec/c_spec.rb[1:1]"], reused: true)
    same = result_for(:survived, replacement: "!=", covered_by: ["./spec/c_spec.rb[1:1]"], reused: true)
    text = render(report_of(a, b, c, same))
    expect(text.scan("tests covered this line and still passed").size).to eq(2)
    expect(text.scan("covered this line and passed in an earlier run").size).to eq(1)
    expect(text.index("-> > ")).to be < text.index("c_spec.rb[1:1]")
    # Same-line mutants are ranked (docs/survivor-ranking.md), so their order is not fixed here; each
    # one must still print its own covering tests, in its own order, just above its line.
    evidence = lambda { |shown|
      text[%r{still passed[^\n]*\n((?:\s+\./spec/[^\n]*\n)+)\s+- comparison >= -> #{Regexp.escape(shown)} }, 1]
    }
    expect(evidence.call(">").scan(/a_spec\.rb\[[\d:]+\]/)).to eq(["a_spec.rb[1:1]", "a_spec.rb[1:2]"])
    expect(evidence.call("<=").scan(/a_spec\.rb\[[\d:]+\]/)).to eq(["a_spec.rb[1:2]", "a_spec.rb[1:1]"])
    expect(text.scan("1 test covered this line and passed in an earlier run").size).to eq(1)
  end

  it "says where the run stopped early and which subjects did not run" do
    report = Saboteur::Report.new(results: [result_for(:survived)], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file),
                                  early_stop: Saboteur::EarlyStop.new(reason: "fail_fast", unreached: %w[A#x B#y]))
    text = render(report)
    expect(text).to include("stopped early (--fail-fast): 2 selected subjects did not run",
                            "not run: A#x", "not run: B#y")
  end

  it "points at the mutated line, not the def line" do
    subject = subjects_in("class Kyc\n  def check(a)\n    a + 1\n  end\nend\n").first
    at = subject.file_source.index("+")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 1, replacement: "-")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "arithmetic", edits: [edit])
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived, mutated_source: subject.apply([edit]))
    report = Saboteur::Report.new(results: [result], subjects: [subject], wall_time: 1.0,
                                  root: File.dirname(subject.file))
    expect(render(report)).to include("#{File.basename(subject.file)}:3 in Kyc#check")
  end

  it "lists a per-file score table, worst first, and a status legend" do
    other = subjects_in("class Other\n  def m; 1; end\nend\n").first
    edit = Saboteur::MutationSource::Edit.new(file: other.file, start_byte: other.file_source.index("1"),
                                              end_byte: other.file_source.index("1") + 1, replacement: "2")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: other.id, operator: "literal_number", edits: [edit])
    killed = Saboteur::MutantResult.new(subject: other, mutation:, status: :killed, mutated_source: other.apply([edit]))
    report = Saboteur::Report.new(results: [result_for(:survived), killed], subjects: [person_subject, other],
                                  wall_time: 1.0, root: File.dirname(person_subject.file))
    text = render(report)
    expect(text).to include("Score by file (worst first):", "legend: killed: a test failed")
    expect(text.index("person.rb  ")).to be < text.index("#{File.basename(other.file)}  ")
  end

  it "adds no colour codes when colour is off, and colours when it is on" do
    report = report_of(result_for(:survived))
    expect(render(report, color: :never)).not_to include("\e[")
    expect(render(report, color: :always)).to include("\e[31m")
  end

  it "lists ran-at-load and unreachable mutants apart, out of the score" do
    text = render(report_of(result_for(:killed),
                            result_for(:ran_at_load, reason: Saboteur::Selection::CoverageMap::RAN_AT_LOAD),
                            result_for(:unreachable, reason: "a captured Method still calls the original")))
    expect(text).to include(
      "killed 1  survived 0  timeout 0  resource limit 0  error 0  skipped 0  ran at load 1  unreachable 1",
      "Ran at load (out of the score):", "Unreachable (out of the score):",
      "hint: ran at load:", "score 100.0 %"
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
    text = verbose_render(report_of(result_for(:killed, kill_cause: "assertion"),
                                    result_for(:killed, replacement: "<", kill_cause: "NoMethodError"),
                                    result_for(:killed, replacement: "<=", kill_cause: "NoMethodError")))
    expect(text).to include("kills: 1 by a failed assertion, 2 by a crash (NoMethodError 2)",
                            "crash kills by operator: comparison 2 of 3")
  end

  it "lists the tests that covered a survivor's line and still passed, top 5" do
    tests = (1..7).map { |n| "./spec/person_spec.rb[1:#{n}]" }
    text = render(report_of(result_for(:survived, covered_by: tests)))
    expect(text).to include("7 tests covered this line and still passed",
                            "  ./spec/person_spec.rb[1:1]", "  ./spec/person_spec.rb[1:5]",
                            "... 2 more in the JSON report (coveredBy)")
    expect(text).not_to include("person_spec.rb[1:6]")
  end

  it "lists exactly five covering tests with no 'more' line, and six with one" do
    five = (1..5).map { |n| "./spec/person_spec.rb[1:#{n}]" }
    expect(render(report_of(result_for(:survived, covered_by: five)))).to include("5 tests covered", "[1:5]")
      .and(satisfy { |text| !text.include?("more in the JSON report (coveredBy)") })
    six = render(report_of(result_for(:survived, covered_by: five + ["./spec/person_spec.rb[1:6]"])))
    expect(six).to include("6 tests covered", "... 1 more in the JSON report (coveredBy)")
    expect(six).not_to include("[1:6]\n")
  end

  it "says tests for two covering tests and test for one" do
    two = render(report_of(result_for(:survived, covered_by: ["./a_spec.rb[1:1]", "./a_spec.rb[1:2]"])))
    expect(two).to include("2 tests covered this line")
    expect(two).not_to include("2 test covered")
  end

  it "says a reused survivor's tests passed in an earlier run" do
    text = render(report_of(result_for(:survived, reused: true, covered_by: ["./spec/person_spec.rb[1:1]"])))
    expect(text).to include("1 test covered this line and passed in an earlier run (--incremental)")
  end

  it "says test, not tests, for one covering test" do
    text = render(report_of(result_for(:survived, covered_by: ["./spec/person_spec.rb[1:1]"])))
    expect(text).to include("1 test covered this line and still passed")
    expect(text).not_to include("more in the JSON report (coveredBy)")
  end

  it "prints no passing-test list for a survivor with no recorded covering tests" do
    expect(render(report_of(result_for(:survived)))).not_to include("still passed")
  end

  it "does not list covering tests for a killed mutant" do
    text = render(report_of(result_for(:killed, covered_by: ["./spec/person_spec.rb[1:1]"])))
    expect(text).not_to include("still passed")
  end

  it "splits the score into assertion and crash shares" do
    text = verbose_render(report_of(result_for(:killed, kill_cause: "assertion"),
                                    result_for(:killed, replacement: "<", kill_cause: "NoMethodError")))
    expect(text).to include("score 100.0 % (assertion 50.0 %, crash 50.0 %)")
  end

  it "names timeouts and kills with no recorded cause in the split" do
    text = verbose_render(report_of(result_for(:killed, kill_cause: "assertion"),
                                    result_for(:timeout, replacement: "<"),
                                    result_for(:killed, replacement: "<=")))
    expect(text).to include("(assertion 33.3 %, crash 0.0 %, timeout 33.3 %, cause not recorded 33.3 %)")
  end

  it "scores whole-body mutants apart even when no kill has a recorded cause" do
    text = verbose_render(report_of(result_for(:killed, coarse: true), result_for(:killed, replacement: "<"),
                                    result_for(:survived, replacement: "==")))
    expect(text).to include("score without whole-body mutants 50.0 % (2 mutants); " \
                            "whole-body mutants alone 100.0 % (1)")
  end

  it "scores whole-body mutants apart in a run of timeouts only" do
    text = verbose_render(report_of(result_for(:timeout, coarse: true), result_for(:timeout, replacement: "<")))
    expect(text).to include("score without whole-body mutants 100.0 % (1 mutants); " \
                            "whole-body mutants alone 100.0 % (1)")
  end

  it "prints no whole-body line when the run has only whole-body mutants" do
    text = render(report_of(result_for(:killed, coarse: true, kill_cause: "assertion"),
                            result_for(:survived, coarse: true, replacement: "==")))
    expect(text).not_to include("without whole-body mutants")
  end

  it "prints no whole-body line when the run has only fine mutants" do
    text = render(report_of(result_for(:killed, kill_cause: "assertion"),
                            result_for(:survived, replacement: "==")))
    expect(text).not_to include("without whole-body mutants")
  end

  it "prints no whole-body line when the only whole-body mutant errored" do
    text = render(report_of(result_for(:error, coarse: true), result_for(:killed, kill_cause: "assertion")))
    expect(text).not_to include("without whole-body mutants")
  end

  it "leaves the split out when no kill has a recorded cause" do
    expect(verbose_render(report_of(result_for(:killed)))).to include("score 100.0 % (killed+timeout)")
  end

  it "scores the whole-body mutants on their own line" do
    text = verbose_render(report_of(result_for(:killed, coarse: true, kill_cause: "NoMethodError"),
                                    result_for(:killed, replacement: "<", kill_cause: "assertion"),
                                    result_for(:survived, replacement: "==")))
    expect(text).to include("score 66.7 % (assertion 33.3 %, crash 33.3 %)",
                            "score without whole-body mutants 50.0 % (assertion 50.0 %, crash 0.0 %) " \
                            "(2 mutants); whole-body mutants alone 100.0 % (1)")
  end

  it "shows every survivor on a line in review mode, with no truncation note" do
    survivors = [result_for(:survived, replacement: ">"), result_for(:survived, replacement: "<=")]
    report = Saboteur::Report.new(results: survivors, subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), review: true)
    text = render(report)
    expect(text.scan("- comparison").size).to eq(2)
    expect(text).not_to include("more survivor", "in the JSON report\n")
  end

  it "shows an ignored survivor next to a live one on the same line in review mode" do
    ignored = result_for(:survived, replacement: ">")
    ignored.ignored = "equivalent"
    live = result_for(:survived, replacement: "<=")
    report = Saboteur::Report.new(results: [ignored, live], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), review: true)
    text = render(report)
    expect(text).to include("- comparison >= -> <= ", "- comparison >= -> > ", "(ignored: equivalent)")
  end

  it "shows resource-limit stops as their own status" do
    text = render(report_of(result_for(:resource_limit, reason: "process tree reached 70 processes (limit 64)")))
    expect(text).to include("resource limit 1")
  end

  it "prints n/a for the score when nothing ran" do
    expect(render(report_of)).to include("score n/a")
  end
end

RSpec.describe Saboteur::Reporter::Terminal, "details" do
  def render(report, **options)
    StringIO.new.tap { |out| described_class.new(out, **options).call(report) }.string
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

  def verbose_render(report)
    render(report, verbose: true)
  end

  def review(*results)
    Saboteur::Report.new(results:, subjects: [person_subject], wall_time: 1.0,
                         root: File.dirname(person_subject.file), review: true)
  end

  def review_with_changes(changed_lines, *results)
    scope = Saboteur::Engine::DiffScope.new({ person_subject.file => Set.new(changed_lines) })
    Saboteur::Report.new(results:, subjects: [person_subject], wall_time: 1.0,
                         root: File.dirname(person_subject.file), review: true, diff_scope: scope)
  end

  it "names the changed line a survivor touches in diff mode" do
    text = render(review_with_changes([2], result_for(:survived)))
    expect(text).to include("changed line: person.rb:2")
  end

  def multi_line_report(changed)
    subject = subjects_in("class K\n  def m(a)\n    a +\n      1 +\n      2 +\n      3 +\n      4\n  end\nend\n").first
    start = subject.file_source.index("a +")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: start,
                                              end_byte: subject.file_source.index("4") + 1, replacement: "0")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits))
    scope = Saboteur::Engine::DiffScope.new({ subject.file => Set.new(changed) })
    [Saboteur::Report.new(results: [result], subjects: [subject], wall_time: 1.0,
                          root: File.dirname(subject.file), review: true, diff_scope: scope),
     File.basename(subject.file)]
  end

  it "caps the changed lines it names at three and counts the rest" do
    report, name = multi_line_report([3, 4, 5, 6, 7])
    expect(render(report)).to include("changed lines: #{name}:3, #{name}:4, #{name}:5 (+2 more)")
  end

  it "names exactly three changed lines with no 'more' note, and four with '+1 more'" do
    report, name = multi_line_report([3, 4, 5])
    expect(render(report)).to include("changed lines: #{name}:3, #{name}:4, #{name}:5\n")
    four, = multi_line_report([3, 4, 5, 6])
    expect(render(four)).to include("#{name}:5 (+1 more)\n")
  end

  it "says 'changed lines' for two lines and 'changed line' for one" do
    two, name = multi_line_report([3, 4])
    expect(render(two)).to include("changed lines: #{name}:3, #{name}:4\n")
    one, = multi_line_report([4])
    expect(render(one)).to include("changed line: #{name}:4\n")
  end

  it "prints no changed line outside diff mode" do
    expect(render(report_of(result_for(:survived)))).not_to include("changed line")
  end

  it "prints no changed line for a mutant that touches none" do
    expect(render(review_with_changes([1], result_for(:survived)))).not_to include("changed line")
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
    expect(verbose_render(report_of(result_for(:survived)))).not_to include("kills:")
    text = verbose_render(report_of(result_for(:killed, kill_cause: "assertion")))
    expect(text).to include("kills: 1 by a failed assertion, 0 by a crash\n")
    expect(text).not_to include("crash kills by operator")
  end

  it "lists only operators that crash-killed" do
    text = verbose_render(report_of(result_for(:killed, kill_cause: "TypeError"),
                                    mutant(:killed, at: "@age", replacement: "1", operator: "other",
                                                    kill_cause: "assertion")))
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
    expect(render(report_of(result_for(:killed)))).not_to include("Survivors (")
    expect(render(report_of(result_for(:survived)))).to include("Survivors (1):\n")
  end

  it "shows three survivors on one line in review mode, in ranked order (ties by digest)" do
    results = [">", "<=", "=="].map { |replacement| result_for(:survived, replacement: replacement) }
    text = render(review(*results))
    expect(text.scan("- comparison").size).to eq(3)
    expect(text.scan(/ >= -> (\S+) /).flatten)
      .to eq(results.sort_by(&:digest).map { |result| result.mutation.edits.first.replacement })
  end

  it "shows every survivor, with no 'more' note, outside review mode" do
    text = render(report_of(result_for(:survived), result_for(:survived, replacement: "<=")))
    expect(text.scan("- comparison").size).to eq(2)
    expect(text).not_to include("more survivor")
  end

  it "prints no errors section and no ignored note when there is nothing to say" do
    text = render(report_of(result_for(:survived)))
    expect(text).not_to include("Errors", "ignored:")
  end

  it "shows survivors on different lines in review mode" do
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
    expect(render(report).scan("- arithmetic").size).to eq(2)
  end
  it "omits absent out-of-score counts, sections and hints" do
    text = render(report_of(result_for(:killed)))
    expect(text).not_to include("ran at load", "unreachable", "out of the score", "hint:")
  end

  it "prints the mutant and location under each out-of-score heading" do
    result = result_for(:unreachable, reason: "captured definition at person.rb:2")
    text = render(report_of(result))
    expect(text).to include("Unreachable (out of the score):\n",
                            "  Person#adult? comparison #{result.digest} person.rb:2\n")
    expect(text).to include("hint: captured definition at person.rb:2")
    expect(text).not_to include("Ran at load (out of the score):")
  end

  it "does not print a hint when an out-of-score result has no reason" do
    expect(render(report_of(result_for(:unreachable)))).not_to include("hint:")
  end
end

RSpec.describe Saboteur::Reporter::Terminal, "hazard suppressions (issue #102)" do
  let(:out) { StringIO.new }

  def render(report)
    described_class.new(out).call(report)
    out.string
  end

  it "prints the suppressed count when positive" do
    report = report_of(result_for(:killed, runtime: 0.1))
    report_with = Saboteur::Report.new(results: report.results, subjects: report.subjects,
                                       wall_time: 1.0, root: Dir.pwd, seed: 1, hazard_suppressions: 3)
    expect(render(report_with)).to include("hazardous mutations suppressed: 3")
  end

  it "stays quiet when nothing was suppressed" do
    expect(render(report_of(result_for(:killed, runtime: 0.1)))).not_to include("hazardous mutations suppressed")
  end
end
