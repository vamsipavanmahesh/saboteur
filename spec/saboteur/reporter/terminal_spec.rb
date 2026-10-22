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
      "1 subject, 2 mutants, wall 1.25 s, seed 1 (repeat with --seed 1)",
      "Score: 50.0% (1/2 killed, tested subjects)",
      "saboteur: 1 killed, 1 survived in 1s - score 50.0%",
      "mean time per executed mutant 0.500 s",
      "1. person.rb:2 Person#adult?",
      "-   2 def adult?; @age >= 18; end",
      "+   2 def adult?; @age > 18; end"
    )
  end

  it "counts selected versus attempted mutants in the headline when the run stopped early (#582)" do
    stop = Saboteur::EarlyStop.new(reason: "fail_fast", unreached: ["Other#x"], truncated: [], unverified: [],
                                   planned_mutants: 57)
    stopped = Saboteur::Report.new(results: [result_for(:killed), result_for(:survived),
                                             result_for(:killed), result_for(:survived)],
                                   subjects: [person_subject, person_subject, person_subject], wall_time: 1.25,
                                   root: File.dirname(person_subject.file), seed: 1, early_stop: stop)
    expect(render(stopped)).to include("3 subjects, 57 mutants selected, 4 attempted, wall 1.25 s")

    out.truncate(0)
    out.rewind
    # C9: each count pluralizes on its own - singular mutant with plural
    # subjects, and the selected/attempted line at one planned mutant.
    two_one = Saboteur::Report.new(results: [result_for(:killed)],
                                   subjects: [person_subject, person_subject], wall_time: 1.25,
                                   root: File.dirname(person_subject.file), seed: 1)
    expect(render(two_one)).to include("2 subjects, 1 mutant, wall 1.25 s")

    out.truncate(0)
    out.rewind
    one_planned = Saboteur::EarlyStop.new(reason: "fail_fast", unreached: ["Other#x"], truncated: [],
                                          unverified: [], planned_mutants: 1)
    planned = Saboteur::Report.new(results: [], subjects: [person_subject], wall_time: 1.25,
                                   root: File.dirname(person_subject.file), seed: 1, early_stop: one_planned)
    expect(render(planned)).to include("1 subject, 1 mutant selected, 0 attempted, wall 1.25 s")

    out.truncate(0)
    out.rewind
    # A stop without a planned count (budget exhausted in a pre-run phase)
    # keeps the plain headline.
    uncounted = Saboteur::EarlyStop.new(reason: "max_duration", unreached: ["Other#x"], truncated: [],
                                        unverified: [])
    partial = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.25,
                                   root: File.dirname(person_subject.file), seed: 1, early_stop: uncounted)
    expect(render(partial)).to include("1 subject, 1 mutant, wall 1.25 s")

    out.truncate(0)
    out.rewind
    # A stop announced after the last planned mutant ran is not a selection
    # mismatch.
    full = Saboteur::EarlyStop.new(reason: "fail_fast", unreached: [], truncated: [], unverified: ["Other#x"],
                                   planned_mutants: 1)
    covered = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.25,
                                   root: File.dirname(person_subject.file), seed: 1, early_stop: full)
    expect(render(covered)).to include("1 subject, 1 mutant, wall 1.25 s")

    out.truncate(0)
    out.rewind
    # A planned count below the attempted count is stale bookkeeping, not a
    # selection mismatch: keep the plain headline rather than printing
    # nonsense like "1 mutants selected, 2 attempted".
    undercounted = Saboteur::EarlyStop.new(reason: "fail_fast", unreached: ["Other#x"], truncated: [],
                                           unverified: [], planned_mutants: 1)
    over = Saboteur::Report.new(results: [result_for(:killed), result_for(:survived)],
                                subjects: [person_subject], wall_time: 1.25,
                                root: File.dirname(person_subject.file), seed: 1, early_stop: undercounted)
    expect(render(over)).to include("1 subject, 2 mutants, wall 1.25 s")
  end

  it "omits the seed clause when the run has no seed" do
    seedless = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.25,
                                    root: File.dirname(person_subject.file))
    text = render(seedless)
    expect(text).to include("1 subject, 1 mutant, wall 1.25 s")
    expect(text).not_to include(", seed")
  end

  it "prints the shard line only for a sharded run" do
    shard = Saboteur::Engine::Shard.parse("1/2")
    allow(shard).to receive(:line).and_return("Shard 1/2: 3 of 10 planned mutants; inventory sha256:abc; partial run")
    sharded = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject], wall_time: 1.0,
                                   root: File.dirname(person_subject.file), seed: 1, shard: shard)
    expect(render(sharded)).to include(shard.line)
    out.truncate(0)
    out.rewind
    expect(render(report_of(result_for(:killed)))).not_to include("partial run")
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

  it "ends a run with the canonical line, then the verdict, then the next steps" do
    text = render(report_of(result_for(:killed), result_for(:survived)))
    expect(text.index("saboteur: 1 killed, 1 survived")).to be < text.index("Next steps:")
  end

  it "prints the complete replay command when the run provides one (#261)" do
    text = render(report_of(result_for(:survived)),
                  replay_command: ->(digest) { "saboteur run --id #{digest} --since main --test spec/a_spec.rb" })
    expect(text).to include("replay one survivor: saboteur run --id ")
    expect(text).to include("--since main --test spec/a_spec.rb")
    expect(text).not_to include("add this run's own")
  end

  it "falls back to the digest-only hint when no replay command builder is wired" do
    text = render(report_of(result_for(:survived)), replay_command: ->(_digest) {})
    expect(text).to include("(add this run's own --config, --since, --subject, --test and source options)")
  end

  it "prints the full replay command however long it gets (#261)" do
    command = "saboteur run --id abc #{'--test spec/dir\\ with\\ spaces/a_spec.rb ' * 40}--seed 1"
    text = render(report_of(result_for(:survived)), replay_command: ->(_digest) { command })
    expect(command.bytesize).to be > 1024
    expect(text).to include("replay one survivor: #{command}")
    expect(text).not_to include("add this run's own")
  end

  it "appends the equivalence-confirmation hint to a chain_removal survivor (#264)" do
    text = render(report_of(result_for(:survived, operator: "chain_removal")))
    expect(text).to include("→ try the shorter chain's value against the longer one; if you confirm the " \
                            "shorter chain is equivalent across the intended inputs")
  end

  it "leaves the next steps out of a clean run" do
    expect(render(report_of(result_for(:killed)))).not_to include("Next steps:")
  end

  it "prints survivors before the summary, and keeps debug statistics out of the default report" do
    text = render(report_of(result_for(:killed, runtime: 0.5), result_for(:survived, runtime: 0.5)))
    expect(text.index("Survivors (1) ")).to be < text.index("saboteur ")
    expect(text).not_to include("mean time per executed mutant", "kills rejected", "(killed+timeout)/")
  end

  it "shows the mutated line in a fence, one block per statement, with a hint and the caveat" do
    results = [result_for(:survived), result_for(:survived, replacement: "<=")]
    text = render(report_of(*results))
    expect(text.scan(/^\d+\. person\.rb:2 Person#adult\?/).size).to eq(1)
    expect(text).to include("-   2 def adult?; @age >= 18; end", "+   2 def adult?; @age ",
                            "→ try an example at the boundary", "Hints are suggestions, not diagnoses",
                            "1 more mutant here:")
    results.each { |result| expect(text).to include(result.digest) }
  end

  it "collapses survivors to one block per statement unless --all-mutants (#1065)" do
    results = [result_for(:survived, covered_by: ["./spec/person_spec.rb[1:1]"]),
               result_for(:survived, replacement: "<=", covered_by: ["./spec/person_spec.rb[1:1]"])]
    collapsed = render(report_of(*results))
    expect(collapsed.scan(/^\d+\. person\.rb:2 Person#adult\?/).size).to eq(1)
    expect(collapsed).to include("1 more mutant here:", "expand: saboteur run --all-mutants")
    out.truncate(0)
    out.rewind
    expanded = render(report_of(*results), all_mutants: true)
    expect(expanded.scan(/^\d+\. person\.rb:2 Person#adult\?/).size).to eq(2)
    expect(expanded).not_to include("more mutant here")
  end

  it "words the timeout legend as an exceeded deadline, not a hang" do
    text = render(report_of(result_for(:timeout)))
    expect(text).to include("1 timeout")
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

  it "collapses same-line survivors into one block with the representative's covering tests (#502)" do
    a = result_for(:survived, replacement: ">", covered_by: ["./spec/a_spec.rb[1:1]", "./spec/a_spec.rb[1:2]"])
    b = result_for(:survived, replacement: "<=", covered_by: ["./spec/a_spec.rb[1:2]", "./spec/a_spec.rb[1:1]"])
    c = result_for(:survived, replacement: "==", covered_by: ["./spec/c_spec.rb[1:1]"], reused: true)
    same = result_for(:survived, replacement: "!=", covered_by: ["./spec/c_spec.rb[1:1]"], reused: true)
    d = result_for(:survived, replacement: "!=", covered_by: ["./spec/d_spec.rb[1:1]"])
    text = render(report_of(a, b, c, same, d))
    expect(text.scan(/^\d+\. person\.rb/).size).to eq(1)
    expect(text.scan("covered by ").size).to eq(1)
    expect(text).to include("+3 more covered, all passed", "4 more mutants here:")
    expect(text).to include("(+1 more)")
    [a, b, c, same, d].each { |result| expect(text).to include(result.digest) }
  end

  it "renders a removal edit as a -/+ pair with the deleted text gone (#502)" do
    removal = result_for(:survived, replacement: "", operator: "element_removal")
    text = render(report_of(removal))
    expect(text).to include("-   2 def adult?; @age >= 18; end", "+   2 def adult?; @age  18; end")
    expect(text).not_to include("-> ")
  end

  it "says where the run stopped early and which subjects did not run" do
    report = Saboteur::Report.new(results: [result_for(:survived)], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file),
                                  early_stop: Saboteur::EarlyStop.new(reason: "fail_fast", unreached: %w[A#x B#y],
                                                                      truncated: [], unverified: []))
    text = render(report)
    expect(text).to include("stopped early (--fail-fast): 2 selected subjects did not run",
                            "not run: A#x", "not run: B#y")
    expect(text).not_to include("partial:")
  end

  it "headlines when the spent budget left no mutants run (#637)" do
    stop = Saboteur::EarlyStop.new(reason: "max_duration", unreached: [person_subject.id],
                                   truncated: [], unverified: [])
    report = Saboteur::Report.new(results: [], subjects: [person_subject], wall_time: 1,
                                  root: File.dirname(person_subject.file), early_stop: stop)
    text = render(report)
    expect(text).to include("no mutants ran before the --max-duration budget was spent; there is no score to judge")
    expect(text).to include("partial: mutant count unknown")
  end

  it "keeps the plain partial line when mutants were judged before the budget stop (#637)" do
    stop = Saboteur::EarlyStop.new(reason: "max_duration", unreached: [], truncated: [], unverified: [])
    report = Saboteur::Report.new(results: [result_for(:survived)], subjects: [person_subject], wall_time: 1,
                                  root: File.dirname(person_subject.file), early_stop: stop)
    expect(render(report)).not_to include("no mutants ran")
  end

  it "names an unknown plan when the budget stops before planning (#654)" do
    stop = Saboteur::EarlyStop.new(reason: "max_duration", unreached: [person_subject.id],
                                   truncated: [], unverified: [])
    report = Saboteur::Report.new(results: [], subjects: [person_subject], wall_time: 1,
                                  root: File.dirname(person_subject.file), early_stop: stop)
    expect(render(report)).to include("partial: mutant count unknown; the budget was spent before planning finished")
  end

  it "points at the mutated line, not the def line" do
    subject = subjects_in("class Kyc\n  def check(a)\n    a + 1\n  end\nend\n").first
    at = subject.file_source.index("+")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 1, replacement: "-")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "arithmetic", edits: [edit])
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived, mutated_source: subject.apply([edit]))
    report = Saboteur::Report.new(results: [result], subjects: [subject], wall_time: 1.0,
                                  root: File.dirname(subject.file))
    expect(render(report)).to include("#{File.basename(subject.file)}:3 Kyc#check")
  end

  it "lists a per-file score table, worst first" do
    other = subjects_in("class Other\n  def m; 1; end\nend\n").first
    edit = Saboteur::MutationSource::Edit.new(file: other.file, start_byte: other.file_source.index("1"),
                                              end_byte: other.file_source.index("1") + 1, replacement: "2")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: other.id, operator: "literal_number", edits: [edit])
    killed = Saboteur::MutantResult.new(subject: other, mutation:, status: :killed, mutated_source: other.apply([edit]))
    report = Saboteur::Report.new(results: [result_for(:survived), killed], subjects: [person_subject, other],
                                  wall_time: 1.0, root: File.dirname(person_subject.file))
    text = render(report)
    expect(text).to include("Score by file (worst first):")
    expect(text.index("person.rb  ")).to be < text.index("#{File.basename(other.file)}  ")
  end

  it "adds no colour codes when colour is off, and colours when it is on" do
    report = report_of(result_for(:survived))
    expect(render(report, color: :never)).not_to include("\e[")
    expect(render(report, color: :always)).to include("\e[31;1m")
  end

  it "repaints a token end to end through overrides" do
    report = report_of(result_for(:survived))
    expect(render(report, color: :always, overrides: { "fail" => :magenta })).to include("\e[35m")
  end

  it "paints the early-stop line warn when colour is on" do
    stop = Saboteur::EarlyStop.new(reason: "fail_fast", unreached: ["Other#x"], truncated: [], unverified: [],
                                   planned_mutants: 57)
    stopped = Saboteur::Report.new(results: [result_for(:killed), result_for(:survived)],
                                   subjects: [person_subject, person_subject], wall_time: 1.25,
                                   root: File.dirname(person_subject.file), seed: 1, early_stop: stop)
    text = render(stopped, color: :always)
    expect(text).to include("\e[33mstopped early")
    expect(text).to include("the score below covers only completed work")
  end

  it "lists ran-at-load and unreachable mutants apart, out of the score" do
    text = render(report_of(result_for(:killed),
                            result_for(:ran_at_load, reason: Saboteur::Selection::CoverageMap::RAN_AT_LOAD),
                            result_for(:unreachable, reason: "a captured Method still calls the original")))
    expect(text).to include(
      "Ran at load (out of the score):", "Unreachable (out of the score):",
      "hint: ran at load:", "Score: 100.0% (1/1 killed, tested subjects)"
    )
  end

  it "lists errors separately and does not call them killed" do
    text = render(report_of(result_for(:error, reason: "child killed by signal 9 during tests")))
    expect(text).to include("1 error", "Errors (not counted as killed):", "signal 9")
    expect(text).not_to include("1 killed")
  end

  # A rejected kill's reason carries the child's full failure detail: the
  # terminal report keeps it as indented continuation lines (#296).
  it "prints every line of a multiline error reason, indented under the mutant (#296)" do
    detail = "killing test t1 also fails with the method unchanged: NameError: uninitialized constant X\n" \
             "./spec/x_spec.rb:4:in `block'\n./spec/x_spec.rb:9:in `block'"
    text = render(report_of(result_for(:error, reason: detail)))
    expect(text).to include("NameError: uninitialized constant X\n    ./spec/x_spec.rb:4:in `block'\n    " \
                            "./spec/x_spec.rb:9:in `block'")
  end

  it "prints the error header format and every continuation line exactly once, stripped (#296)" do
    detail = "RuntimeError: boom\n  ./spec/x_spec.rb:4:in `block'\n    ./spec/x_spec.rb:9:in `block'"
    result = result_for(:error, reason: detail)
    text = render(report_of(result))
    header = "  #{result.subject.id} #{result.mutation.operator} #{result.digest}: RuntimeError: boom"
    block = "\nErrors (not counted as killed):\n#{header}\n    ./spec/x_spec.rb:4:in `block'\n    " \
            "./spec/x_spec.rb:9:in `block'\n"
    expect(text).to include(block)
  end

  it "adds an unverified count to the summary line when some mutants ran unverified (#296)" do
    line = render(report_of(result_for(:killed), result_for(:unverified))).lines.find do |l|
      l.start_with?("saboteur: ")
    end
    expect(line).to include("1 unverified")
  end

  it "omits the unverified count from the summary line when none ran unverified (#296)" do
    line = render(report_of(result_for(:killed))).lines.find { |l| l.start_with?("saboteur: ") }
    expect(line).not_to include("unverified")
  end

  it "shows skip reasons, warnings and ignored survivors" do
    survivor = result_for(:survived)
    survivor.ignored = "equivalent: ages are integers"
    text = render(report_of(survivor, result_for(:skipped, reason: "no coverage"), warnings: ["stale entry"]),
                  verbose: true)
    expect(text).to include("1 accepted", "mutant locations not reached: 1", "warning: stale entry",
                            %(Accepted (1, not scored): person.rb:2 comparison - "equivalent: ages are integers"))
  end

  it "prints other mutant skip reasons with the generic wording (#1087)" do
    text = render(report_of(result_for(:skipped, reason: "filtered")), verbose: true)
    expect(text).to include("skipped: filtered: 1")
  end

  it "starts no CI workflow command from repository text the report prints (#834)" do
    text = render(report_of(result_for(:killed), warnings: ["x\n::error::injected", "see ##[error]y"]))
    expect(text).to include("warning: x\n\\x3a:error::injected", "warning: see ##\\x5berror]y")
    expect(text).not_to match(/^::error/)
  end

  it "does not reprint live-announced warnings, but keeps the rest (#605)" do
    text = render(report_of(result_for(:killed), warnings: ["stale entry", "inferred specs: running only x"],
                                                 live_announced: ["inferred specs: running only x"]))
    expect(text).to include("warning: stale entry")
    expect(text).not_to include("inferred specs: running only")
  end

  it "counts a kill without a recorded cause as such, not as an assertion kill" do
    text = verbose_render(report_of(result_for(:killed), result_for(:survived, kill_cause: "assertion")))
    expect(text).to include("kills: 0 by a failed assertion, 0 by a crash, 1 with cause not recorded\n")
  end

  it "adds the cause-not-recorded count after the crash classes" do
    text = verbose_render(report_of(result_for(:killed, kill_cause: "assertion"),
                                    result_for(:killed, replacement: "<", kill_cause: "NoMethodError"),
                                    result_for(:killed, replacement: "<=")))
    expect(text).to include("kills: 1 by a failed assertion, 1 by a crash (NoMethodError 1), " \
                            "1 with cause not recorded\n")
  end

  it "splits kills into assertion kills and crash kills, by operator" do
    text = verbose_render(report_of(result_for(:killed, kill_cause: "assertion"),
                                    result_for(:killed, replacement: "<", kill_cause: "NoMethodError"),
                                    result_for(:killed, replacement: "<=", kill_cause: "NoMethodError")))
    expect(text).to include("kills: 1 by a failed assertion, 2 by a crash (NoMethodError 2)",
                            "crash kills by operator: comparison 2 of 3")
  end

  it "orders crash classes by count, most frequent first" do
    text = verbose_render(report_of(result_for(:killed, kill_cause: "TypeError"),
                                    result_for(:killed, replacement: "<", kill_cause: "NoMethodError"),
                                    result_for(:killed, replacement: "<=", kill_cause: "NoMethodError")))
    expect(text).to include("kills: 0 by a failed assertion, 3 by a crash (NoMethodError 2, TypeError 1)\n")
  end

  it "joins the crash-kill counts of two operators with a comma" do
    text = verbose_render(report_of(result_for(:killed, kill_cause: "NoMethodError", operator: "insert"),
                                    result_for(:killed, replacement: "<", kill_cause: "NoMethodError"),
                                    result_for(:killed, replacement: "<=", kill_cause: "TypeError")))
    expect(text).to include("crash kills by operator: insert 1 of 1, comparison 2 of 2\n")
  end

  it "names the first covering test and counts the rest" do
    tests = (1..7).map { |n| "./spec/person_spec.rb[1:#{n}]" }
    text = render(report_of(result_for(:survived, covered_by: tests)))
    expect(text).to include("covered by ./spec/person_spec.rb[1:1] - ran, still passed",
                            "+6 more covered, all passed")
    expect(text).not_to include("person_spec.rb[1:2]")
  end

  it "counts every covering test beyond the first" do
    five = (1..5).map { |n| "./spec/person_spec.rb[1:#{n}]" }
    five_text = render(report_of(result_for(:survived, covered_by: five)))
    expect(five_text.scan("covered by ").size).to eq(1)
    expect(five_text).to include("+4 more covered, all passed")
    six = render(report_of(result_for(:survived, covered_by: five + ["./spec/person_spec.rb[1:6]"])))
    expect(six).to include("+5 more covered, all passed")
    expect(six).not_to include("[1:2]")
  end

  it "groups same-line survivors whose covering-test sets differ only by duplicates (#539)" do
    a = result_for(:survived, replacement: ">", covered_by: ["./spec/a_spec.rb[1:1]", "./spec/a_spec.rb[1:1]"])
    b = result_for(:survived, replacement: "<=", covered_by: ["./spec/a_spec.rb[1:1]"])
    text = render(report_of(a, b))
    expect(text.scan(/^\d+\. person\.rb/).size).to eq(1)
    expect(text.scan("covered by ").size).to eq(1)
    expect(text).to include("1 more mutant here:")
  end

  it "collapses same-line survivors even when only their reuse differs (#539)" do
    a = result_for(:survived, replacement: ">", covered_by: ["./spec/a_spec.rb[1:1]"], reused: true)
    b = result_for(:survived, replacement: "<=", covered_by: ["./spec/a_spec.rb[1:1]"])
    text = render(report_of(a, b))
    expect(text.scan(/^\d+\. person\.rb/).size).to eq(1)
    expect(text.scan("covered by ").size).to eq(1)
    expect(text).to include("1 more mutant here:")
  end

  it "shows the representative's changed lines for a collapsed same-line block (#539)" do
    subject = subjects_in("class K\n  def m(a)\n    a +\n      1\n  end\nend\n").first
    plus = subject.file_source.index("+")
    edit_a = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: plus, end_byte: plus + 1,
                                                replacement: "-")
    mutation_a = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "arithmetic",
                                                        edits: [edit_a])
    span = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: plus,
                                              end_byte: subject.file_source.index("1") + 1, replacement: "0")
    mutation_b = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [span])
    covered = ["./spec/k_spec.rb[1:1]"]
    a = Saboteur::MutantResult.new(subject:, mutation: mutation_a, status: :survived, covered_by: covered,
                                   mutated_source: subject.apply(mutation_a.edits))
    b = Saboteur::MutantResult.new(subject:, mutation: mutation_b, status: :survived, covered_by: covered,
                                   mutated_source: subject.apply(mutation_b.edits))
    scope = Saboteur::Engine::DiffScope.new({ subject.file => Set.new([3, 4]) })
    report = Saboteur::Report.new(results: [a, b], subjects: [subject], wall_time: 1.0,
                                  root: File.dirname(subject.file), review: true, diff_scope: scope)
    name = File.basename(subject.file)
    text = render(report)
    expect(text.scan(/changed lines?:/).size).to eq(1)
    expect(text).to include("changed lines: #{name}:3, #{name}:4")
    expect(text).to include("1 more mutant here:")
  end

  it "says tests for two covering tests and test for one" do
    two = render(report_of(result_for(:survived, covered_by: ["./a_spec.rb[1:1]", "./a_spec.rb[1:2]"])))
    expect(two).to include("covered by ./a_spec.rb[1:1] - ran, still passed", "+1 more covered, all passed")
  end

  it "says a reused survivor's tests passed in an earlier run" do
    text = render(report_of(result_for(:survived, reused: true, covered_by: ["./spec/person_spec.rb[1:1]"])))
    expect(text).to include("covered by ./spec/person_spec.rb[1:1] - passed in an earlier run (--incremental)")
  end

  it "says test, not tests, for one covering test" do
    text = render(report_of(result_for(:survived, covered_by: ["./spec/person_spec.rb[1:1]"])))
    expect(text).to include("covered by ./spec/person_spec.rb[1:1] - ran, still passed")
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
    expect(text).to include("Score: 100.0% (2/2 killed, tested subjects) (assertion 50.0 %, crash 50.0 %)",
                            "(killed+timeout)/(killed+survived+timeout); errors, resource limits and skips excluded")
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

  it "names timeouts in the score parenthetical when one is counted (#1146)" do
    text = render(report_of(result_for(:killed), result_for(:timeout, replacement: "<")))
    expect(text).to include("Score: 100.0% (2/2 killed or timed out, tested subjects)")
    expect(text).not_to include("(2/2 killed,")
  end

  it "leaves the split out when no kill has a recorded cause" do
    expect(verbose_render(report_of(result_for(:killed))))
      .to include("Score: 100.0% (1/1 killed, tested subjects) (killed+timeout)")
  end

  it "scores the whole-body mutants on their own line" do
    text = verbose_render(report_of(result_for(:killed, coarse: true, kill_cause: "NoMethodError"),
                                    result_for(:killed, replacement: "<", kill_cause: "assertion"),
                                    result_for(:survived, replacement: "==")))
    expect(text).to include("Score: 66.7% (2/3 killed, tested subjects) (assertion 33.3 %, crash 33.3 %)",
                            "score without whole-body mutants 50.0 % (assertion 50.0 %, crash 0.0 %) " \
                            "(2 mutants); whole-body mutants alone 100.0 % (1)")
  end

  it "shows every survivor on a line in review mode, with no truncation note" do
    survivors = [result_for(:survived, replacement: ">"), result_for(:survived, replacement: "<=")]
    report = Saboteur::Report.new(results: survivors, subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), review: true)
    text = render(report)
    expect(text.scan(/^\d+\. person\.rb/).size).to eq(1)
    expect(text).to include("1 more mutant here:")
    survivors.each { |result| expect(text).to include(result.digest) }
  end

  it "shows an ignored survivor next to a live one on the same line in review mode" do
    ignored = result_for(:survived, replacement: ">")
    ignored.ignored = "equivalent"
    live = result_for(:survived, replacement: "<=")
    report = Saboteur::Report.new(results: [ignored, live], subjects: [person_subject], wall_time: 1.0,
                                  root: File.dirname(person_subject.file), review: true)
    text = render(report)
    expect(text.scan(/^\d+\. person\.rb/).size).to eq(1)
    expect(text).to include(live.digest, %(Accepted (1, not scored): person.rb:2 comparison - "equivalent"))
    expect(text).not_to include(ignored.digest)
  end

  it "shows resource-limit stops as their own status" do
    text = render(report_of(result_for(:resource_limit, reason: "process tree reached 70 processes (limit 64)")))
    expect(text).to include("1 resource limit")
  end

  it "prints n/a for the score when nothing ran" do
    expect(render(report_of)).to include("Score: n/a - nothing tested")
  end

  # 31 errored + 9 killed prints "score 100.0 %" over "the run tested almost
  # nothing": the share covers only scored mutants, so an error-dominated
  # run says so instead of quoting a perfect score (#557).
  it "prints the scored share, not a bare score, when most executed mutants errored" do
    text = render(report_of(result_for(:killed), *Array.new(3) { result_for(:error) }))
    expect(text).to include("Score: n/a (1 of 4 mutants scored, 100.0 % of scored)")
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

  it "names a full incremental invalidation instead of staying silent" do
    report = report_of(result_for(:killed), reuse_label: "--incremental")
    text = render(report)
    expect(text).to include(
      "no verdicts reused from earlier runs (--incremental): first --incremental run, " \
      "or every mutant's inputs changed"
    )
    expect(text).not_to match(/reused 0 of/)
    expect(render(report_of(result_for(:killed)))).not_to include("verdicts")
  end

  it "names the reuse flag that was passed, including --resume" do
    resumed = report_of(result_for(:killed, reused: true), reuse_label: "--resume")
    expect(render(resumed)).to include("reused 1 of 1 verdicts from earlier runs (--resume)")

    cold_resume = report_of(result_for(:killed), reuse_label: "--resume")
    expect(render(cold_resume)).to include("no verdicts reused from earlier runs (--resume): first --resume run")
  end

  it "says nothing about reuse for an empty incremental run" do
    expect(render(report_of(reuse_label: "--incremental"))).not_to include("verdicts")
  end

  it "prints the reuse outcome on a clean run (all killed), where CI lives" do
    clean = render(report_of(result_for(:killed, reused: true), reuse_label: "--incremental"), exit_code: 0)
    expect(clean).to include("reused 1 of 1 verdicts from earlier runs (--incremental)")

    cold = render(report_of(result_for(:killed), reuse_label: "--incremental"), exit_code: 0)
    expect(cold).to include("no verdicts reused from earlier runs (--incremental): first --incremental run")

    expect(render(report_of(result_for(:killed)), exit_code: 0)).not_to include("verdicts")
  end

  it "prints the reuse line for a partially reused non-incremental report" do
    report = report_of(result_for(:killed, reused: true), result_for(:survived))
    expect(render(report)).to include("reused 1 of 2 verdicts from earlier runs (--incremental)")
  end

  it "counts only storable verdicts in the reuse denominator and names the always-rerun rest" do
    report = report_of(result_for(:killed, reused: true), result_for(:survived, reused: true),
                       result_for(:skipped), reuse_label: "--incremental")
    expect(render(report)).to include(
      "reused 2 of 2 verdicts from earlier runs (--incremental); 1 skipped/errored mutant(s) always rerun"
    )
  end

  it "omits the always-rerun suffix when every verdict is storable" do
    report = report_of(result_for(:killed, reused: true), reuse_label: "--incremental")
    text = render(report)
    expect(text).to include("reused 1 of 1 verdicts from earlier runs (--incremental)")
    expect(text).not_to include("always rerun")
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
    expect(render(report_of(result_for(:survived)))).to include("Survivors (1) - changes your tests did not catch\n")
  end

  it "collapses same-line survivors into one block, siblings in ranked order (ties by digest)" do
    results = [">", "<=", "=="].map { |replacement| result_for(:survived, replacement: replacement) }
    text = render(review(*results))
    ordered = results.sort_by(&:digest)
    expect(text.scan(/^\d+\. person\.rb/).size).to eq(1)
    expect(text).to include(ordered[0].digest)
    sibling = text.lines.find { |line| line.include?("more mutants here") }
    expect(sibling).to include("2 more mutants here: #{ordered[1].digest} (comparison), " \
                               "#{ordered[2].digest} (comparison)")
  end

  it "collapses same-line survivors into one block outside review mode too" do
    results = [result_for(:survived), result_for(:survived, replacement: "<=")]
    text = render(report_of(*results))
    expect(text.scan(/^\d+\. person\.rb/).size).to eq(1)
    expect(text).to include("1 more mutant here:")
    results.each { |result| expect(text).to include(result.digest) }
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
    expect(render(report).scan(/^\d+\. \S+:\d+ Two#m/).size).to eq(2)
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

  def render(report, **options)
    described_class.new(out, all_mutants: true, **options).call(report)
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
