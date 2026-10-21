# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe Saboteur::Reporter::SurvivorList do
  after { FileUtils.rm_rf(@dirs.to_a) }

  let(:out) { StringIO.new }
  let(:palette) { Saboteur::Reporter::Palette.new(enabled: false) }

  # A survivor of ">=" -> ">" on the nth ">=" of a two-method source.
  def survivor_in(name, nth: 0, dir: nil, **attributes)
    source = "class K\n  def a; @x >= 1; end\n  def b; @y >= 2; end\nend\n"
    subject = dir ? subjects_in_dir(dir, source, name)[nth] : subjects_in(source, name:)[nth]
    at = subject.file_source.index(">=", subject.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2, replacement: ">")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison", edits: [edit],
                                                      coarse: false)
    Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                               mutated_source: subject.apply(mutation.edits), **attributes)
  end

  def subjects_in_dir(dir, source, name)
    path = File.join(dir, name)
    File.write(path, source)
    Saboteur::SubjectFinder.new.call(path).subjects
  end

  def render(*results)
    out.truncate(0)
    out.rewind
    root = File.dirname(results.first.subject.file)
    report = Saboteur::Report.new(results:, subjects: results.map(&:subject).uniq, wall_time: 1.0, root:,
                                  warnings: [], seed: 1)
    described_class.new(out, palette, all_mutants: true).call(report, results)
    out.string
  end

  it "lists files in name order, whatever order the survivors came in" do
    dir = File.realpath(Dir.mktmpdir("saboteur-spec-"))
    (@dirs ||= []) << dir
    text = render(survivor_in("z.rb", dir:), survivor_in("a.rb", dir:))
    expect(text.index("a.rb\n")).to be < text.index("z.rb\n")
  end

  it "lists the lines of one method in line order and shows each line's own source" do
    subject = subjects_in("class K\n  def a\n    @x >= 1\n    @y >= 2\n  end\nend\n", name: "m.rb").first
    results = [4, 3].map do |line|
      at = subject.file_source.lines.first(line - 1).sum(&:size) + subject.file_source.lines[line - 1].index(">=")
      edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2, replacement: ">")
      mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison", edits: [edit],
                                                        coarse: false)
      Saboteur::MutantResult.new(subject:, mutation:, status: :survived, mutated_source: subject.apply(mutation.edits))
    end
    text = render(*results)
    expect(text.lines.grep(/^      \d+: /)).to eq(["      3: @x >= 1\n", "      4: @y >= 2\n"])
  end

  it "separates the file name, the evidence and the hint with the documented indentation" do
    text = render(survivor_in("p.rb", covered_by: %w[./spec/p_spec.rb[1:1]]))
    expect(text).to start_with("Survivors (1):\n\np.rb\n  K#a\n    p.rb:2 in K#a\n      2: def a; @x >= 1; end\n")
    expect(text).to include(
      "      1 test covered this line and still passed (the missing check may belong in one of them):\n",
      "        ./spec/p_spec.rb[1:1]\n",
      "      - comparison >= -> > "
    )
    expect(text).to include("\n        hint: ")
    expect(text).to include("\n\nHints are suggestions")
  end

  def mutant_on(subject, at, replacement, covered_by: [], reused: false, executed: nil)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 2, replacement:)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison", edits: [edit],
                                                      coarse: false)
    Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                               mutated_source: subject.apply(mutation.edits), covered_by:, reused:, executed:)
  end

  def render_collapsed(*results)
    out.truncate(0)
    out.rewind
    root = File.dirname(results.first.subject.file)
    report = Saboteur::Report.new(results:, subjects: results.map(&:subject).uniq, wall_time: 1.0, root:,
                                  warnings: [], seed: 1)
    described_class.new(out, palette).call(report, results)
    out.string
  end

  it "collapses each statement to one finding with the label mix by default (#1065)" do
    subject = subjects_in("class K\n  def a; @x >= 1; end\nend\n", name: "m.rb").first
    at = subject.file_source.index(">=", subject.start_byte)
    covered = mutant_on(subject, at, ">", covered_by: ["./spec/m_spec.rb[1:1]"])
    plain = mutant_on(subject, at, "<")
    # Insertion order is unlabeled first; the mix prints labels sorted.
    text = render_collapsed(plain, covered)
    expect(text).to include("      - 2 mutants: 1 missing_test, 1 unlabeled\n")
    expect(text).to include(covered.digest, plain.digest)
    expect(text).not_to include("- comparison >= -> >")
  end

  it "unions the covering tests of every mutant on the statement" do
    subject = subjects_in("class K\n  def a; @x >= 1; end\nend\n", name: "m.rb").first
    at = subject.file_source.index(">=", subject.start_byte)
    first = mutant_on(subject, at, ">", covered_by: ["./spec/a_spec.rb[1:1]"])
    second = mutant_on(subject, at, "<", covered_by: ["./spec/b_spec.rb[1:2]", "./spec/a_spec.rb[1:1]"])
    text = render_collapsed(first, second)
    expect(text).to include("      2 tests covered this line and still passed")
    expect(text).to include("./spec/a_spec.rb[1:1]", "./spec/b_spec.rb[1:2]")
  end

  it "names the tests that ran when fewer ran than covered the line" do
    subject = subjects_in("class K\n  def a; @x >= 1; end\nend\n", name: "m.rb").first
    at = subject.file_source.index(">=", subject.start_byte)
    result = mutant_on(subject, at, ">", covered_by: ["./spec/a_spec.rb[1:1]", "./spec/b_spec.rb[1:2]"],
                                         executed: ["./spec/a_spec.rb[1:1]"])
    text = render_collapsed(result)
    expect(text).to include("      1 of the 2 tests that covered this line ran and still passed " \
                            "(the missing check may belong in one of them):\n")
    expect(text).to include("        ./spec/a_spec.rb[1:1]\n")
    expect(text).to include("      did not run: ./spec/b_spec.rb[1:2]\n")
    expect(text).not_to include("2 tests covered this line")
  end

  it "keeps the covered-and-passed line when every covering test ran" do
    subject = subjects_in("class K\n  def a; @x >= 1; end\nend\n", name: "m.rb").first
    at = subject.file_source.index(">=", subject.start_byte)
    result = mutant_on(subject, at, ">", covered_by: ["./spec/a_spec.rb[1:1]"], executed: ["./spec/a_spec.rb[1:1]"])
    text = render_collapsed(result)
    expect(text).to include("      1 test covered this line and still passed")
    expect(text).not_to include("did not run")
  end

  it "caps the did-not-run list at three names" do
    subject = subjects_in("class K\n  def a; @x >= 1; end\nend\n", name: "m.rb").first
    at = subject.file_source.index(">=", subject.start_byte)
    covered = ["./spec/a_spec.rb[1:1]", "./spec/b_spec.rb[1:1]", "./spec/c_spec.rb[1:1]",
               "./spec/d_spec.rb[1:1]", "./spec/e_spec.rb[1:1]"]
    result = mutant_on(subject, at, ">", covered_by: covered, executed: ["./spec/a_spec.rb[1:1]"])
    text = render_collapsed(result)
    expect(text).to include("      did not run: ./spec/b_spec.rb[1:1], ./spec/c_spec.rb[1:1], " \
                            "./spec/d_spec.rb[1:1] (+1 more)\n")
    expect(text).not_to include("./spec/e_spec.rb[1:1]")
  end

  def covered_survivor(covered:, executed:, reused: false)
    subject = subjects_in("class K\n  def a; @x >= 1; end\nend\n", name: "m.rb").first
    at = subject.file_source.index(">=", subject.start_byte)
    mutant_on(subject, at, ">", covered_by: covered, executed:, reused:)
  end

  it "caps the ran list at five and counts the rest" do
    covered = ("a".."h").map { |n| "./spec/#{n}_spec.rb[1:1]" }
    text = render_collapsed(covered_survivor(covered:, executed: covered.first(7)))
    expect(text).to include("      7 of the 8 tests that covered this line ran and still passed " \
                            "(the missing check may belong in one of them):\n")
    expect(text).to include("        ... 2 more in the JSON report (executed)\n")
    expect(text).not_to include("./spec/f_spec.rb", "./spec/g_spec.rb")
    expect(text).to include("      did not run: ./spec/h_spec.rb[1:1]\n")
  end

  it "prints no more-line when five or fewer tests ran" do
    covered = ("a".."f").map { |n| "./spec/#{n}_spec.rb[1:1]" }
    text = render_collapsed(covered_survivor(covered:, executed: covered.first(5)))
    expect(text).to include("      5 of the 6 tests that covered this line ran and still passed")
    expect(text).not_to include("more in the JSON report (executed)")
    expect(text).to include("      did not run: ./spec/f_spec.rb[1:1]\n")
  end

  it "prints no suffix when exactly three tests did not run" do
    covered = ("a".."d").map { |n| "./spec/#{n}_spec.rb[1:1]" }
    text = render_collapsed(covered_survivor(covered:, executed: covered.first(1)))
    expect(text).to include("      did not run: ./spec/b_spec.rb[1:1], ./spec/c_spec.rb[1:1], " \
                            "./spec/d_spec.rb[1:1]\n")
    expect(text).not_to include("+0 more")
  end

  it "words a reused survivor's ran line as an earlier run" do
    covered = ("a".."c").map { |n| "./spec/#{n}_spec.rb[1:1]" }
    text = render_collapsed(covered_survivor(covered:, executed: covered.first(2), reused: true))
    expect(text).to include("      2 of the 3 tests that covered this line " \
                            "passed in an earlier run (--incremental)")
    expect(text).to include("      did not run: ./spec/c_spec.rb[1:1]\n")
  end

  it "keeps the covered line when the run recorded tests outside the covering set" do
    text = render_collapsed(covered_survivor(covered: ["./spec/a_spec.rb[1:1]", "./spec/b_spec.rb[1:1]"],
                                             executed: ["./spec/a_spec.rb[1:1]", "./spec/c_spec.rb[1:1]"]))
    expect(text).to include("      2 tests covered this line and still passed")
    expect(text).not_to include("of the 2 tests", "did not run")
  end

  it "falls back to covering tests for a mutant with no recorded executed tests" do
    subject = subjects_in("class K\n  def a; @x >= 1; end\nend\n", name: "m.rb").first
    at = subject.file_source.index(">=", subject.start_byte)
    first = mutant_on(subject, at, ">", covered_by: ["./spec/a_spec.rb[1:1]"])
    second = mutant_on(subject, at, "<", covered_by: ["./spec/x_spec.rb[1:1]", "./spec/y_spec.rb[1:1]"],
                                         executed: ["./spec/x_spec.rb[1:1]"])
    text = render_collapsed(first, second)
    expect(text).to include("      2 of the 3 tests that covered this line ran and still passed")
    expect(text).to include("      did not run: ./spec/y_spec.rb[1:1]\n")
  end

  it "marks unrun selected tests in the per-mutant evidence too" do
    text = render(survivor_in("p.rb", covered_by: ["./spec/p_spec.rb[1:1]", "./spec/q_spec.rb[1:1]"],
                                      executed: ["./spec/q_spec.rb[1:1]"]))
    expect(text).to include("      1 of the 2 tests that covered this line ran and still passed")
    expect(text).to include("        ./spec/q_spec.rb[1:1]\n")
    expect(text).to include("      did not run: ./spec/p_spec.rb[1:1]\n")
  end

  it "abbreviates a statement's digest list after three" do
    subject = subjects_in("class K\n  def a; @x >= 1; end\nend\n", name: "m.rb").first
    at = subject.file_source.index(">=", subject.start_byte)
    results = [">", "<", "<=", "==", "!="].map { |replacement| mutant_on(subject, at, replacement) }
    text = render_collapsed(*results)
    expect(text).to include("      - 5 mutants: 5 unlabeled\n")
    expect(text).to include("        #{results.first(3).map(&:digest).join(' ')} (+2 more in the JSON report)\n")
    expect(text).not_to include(results[3].digest, results[4].digest)
  end

  it "prints every digest without a suffix when a statement has three mutants" do
    subject = subjects_in("class K\n  def a; @x >= 1; end\nend\n", name: "m.rb").first
    at = subject.file_source.index(">=", subject.start_byte)
    results = [">", "<", "<="].map { |replacement| mutant_on(subject, at, replacement) }
    text = render_collapsed(*results)
    expect(text).to include("        #{results.map(&:digest).join(' ')}\n")
    expect(text).not_to include("more in the JSON report")
  end

  it "takes the covered-by phrase's reuse status from the statement's first mutant" do
    subject = subjects_in("class K\n  def a; @x >= 1; end\nend\n", name: "m.rb").first
    at = subject.file_source.index(">=", subject.start_byte)
    first = mutant_on(subject, at, ">", covered_by: ["./spec/a_spec.rb[1:1]"], reused: true)
    second = mutant_on(subject, at, "<", covered_by: ["./spec/a_spec.rb[1:1]"])
    text = render_collapsed(first, second)
    expect(text).to include("passed in an earlier run (--incremental)")
    expect(render_collapsed(second, first)).to include("still passed")
  end

  it "keeps ignored mutants out of the collapsed finding and lists them per mutant" do
    subject = subjects_in("class K\n  def a; @x >= 1; end\nend\n", name: "m.rb").first
    at = subject.file_source.index(">=", subject.start_byte)
    live = mutant_on(subject, at, ">", covered_by: ["./spec/m_spec.rb[1:1]"])
    accepted = mutant_on(subject, at, "<")
    accepted.ignored = "boundary covered elsewhere"
    text = render_collapsed(live, accepted)
    expect(text).to include("      - 1 mutant: 1 missing_test\n")
    expect(text).to include("      - comparison >= -> < #{accepted.digest} (ignored: boundary covered elsewhere)\n")
    expect(text).not_to include("2 mutants")
  end

  it "renders no collapsed finding when every mutant on the line is ignored" do
    subject = subjects_in("class K\n  def a; @x >= 1; end\nend\n", name: "m.rb").first
    at = subject.file_source.index(">=", subject.start_byte)
    first = mutant_on(subject, at, ">")
    second = mutant_on(subject, at, "<")
    first.ignored = second.ignored = "boundary covered elsewhere"
    text = render_collapsed(first, second)
    expect(text).not_to include("0 mutants")
    expect(text).to include("      - comparison >= -> > #{first.digest} (ignored: boundary covered elsewhere)\n")
    expect(text).to include("      - comparison >= -> < #{second.digest} (ignored: boundary covered elsewhere)\n")
  end

  it "tags each mutant line with its label in --all-mutants mode" do
    text = render(survivor_in("p.rb", covered_by: ["./spec/p_spec.rb[1:1]"]))
    expect(text).to match(/- comparison >= -> > \h+ \[missing_test\]/)
  end

  it "prints the hint caveat when only some survivors carry a hint" do
    ignored = survivor_in("q.rb")
    ignored.ignored = "equivalent"
    expect(render(ignored, survivor_in("r.rb"))).to include("Hints are suggestions")
  end

  # A survivor of one edit in a one-method source, with the evidence the report prints.
  def edited(source, from, to, operator: "comparison", subject: nil, coarse: false, **attributes)
    subject ||= subjects_in(source, name: "e.rb").first
    at = subject.file_source.index(from, subject.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + from.size,
                                              replacement: to)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator:, edits: [edit], coarse:)
    Saboteur::MutantResult.new(subject:, mutation:, status: :survived, mutated_source: subject.apply(mutation.edits),
                               **attributes)
  end

  def render_scoped(results, changed)
    out.truncate(0)
    out.rewind
    subject = results.first.subject
    scope = Saboteur::Engine::DiffScope.new({ subject.file => Set.new(changed) })
    report = Saboteur::Report.new(results:, subjects: [subject], wall_time: 1.0, root: File.dirname(subject.file),
                                  warnings: [], seed: 1, diff_scope: scope)
    described_class.new(out, palette, all_mutants: true).call(report, results)
    out.string
  end

  it "prints nothing when there are no survivors" do
    report = Saboteur::Report.new(results: [], subjects: [], wall_time: 1.0, root: Dir.tmpdir, warnings: [], seed: 1)
    described_class.new(out, palette).call(report, [])
    expect(out.string).to eq("")
  end

  it "ends each mutation line with its digest and an ignored note" do
    result = edited("class K\n  def a; @x >= 1; end\nend\n", ">=", ">")
    expect(render(result)).to include("      - comparison >= -> > #{result.digest}\n")
    result.ignored = "equivalent"
    expect(render(result)).to include("      - comparison >= -> > #{result.digest} (ignored: equivalent)\n")
  end

  it "words a mutation that deletes text as a removal" do
    result = edited("class K\n  def a; @x.to_s.size; end\nend\n", ".to_s", "", operator: "chain_removal")
    expect(render(result)).to include("      - chain_removal removes .to_s #{result.digest}\n")
  end

  it "counts the covering tests and uses the singular for one" do
    source = "class K\n  def a; @x >= 1; end\nend\n"
    one = render(edited(source, ">=", ">", covered_by: %w[./spec/a_spec.rb[1:1]]))
    expect(one).to include("      1 test covered this line and still passed (the missing check")
    two = render(edited(source, ">=", ">", covered_by: %w[./spec/a_spec.rb[1:1] ./spec/a_spec.rb[1:2]]))
    expect(two).to include("      2 tests covered this line and still passed (the missing check")
  end

  it "prints no covering-test block for a mutant no test covered" do
    text = render(edited("class K\n  def a; @x >= 1; end\nend\n", ">=", ">"))
    expect(text).not_to include("covered this line")
  end

  it "lists at most five covering tests and says how many more the JSON report holds" do
    source = "class K\n  def a; @x >= 1; end\nend\n"
    tests = (1..7).map { |n| "./spec/a_spec.rb[1:#{n}]" }
    text = render(edited(source, ">=", ">", covered_by: tests))
    expect(text.lines.grep(%r{^        \./spec/})).to eq(tests.first(5).map { |name| "        #{name}\n" })
    expect(text).to include("        ... 2 more in the JSON report (coveredBy)\n")
    five = render(edited(source, ">=", ">", covered_by: tests.first(5)))
    expect(five).not_to include("more in the JSON report")
    six = render(edited(source, ">=", ">", covered_by: tests.first(6)))
    expect(six).to include("        ... 1 more in the JSON report (coveredBy)\n")
  end

  it "says a reused survivor passed in an earlier run" do
    text = render(edited("class K\n  def a; @x >= 1; end\nend\n", ">=", ">", covered_by: %w[./spec/a_spec.rb[1:1]],
                                                                             reused: true))
    expect(text).to include("1 test covered this line and passed in an earlier run (--incremental)")
  end

  it "names the changed lines in diff mode and abbreviates after three" do
    source = "class K\n  def a\n    [1,\n     2,\n     3,\n     4,\n     5] + @x\n  end\nend\n"
    result = edited(source, "[1,\n     2,\n     3,\n     4,\n     5]", "[]", operator: "array")
    text = render_scoped([result], [3, 4, 5, 6, 7])
    expect(text).to include("      changed lines: e.rb:3, e.rb:4, e.rb:5 (+2 more)\n")
    one = render_scoped([edited("class K\n  def a; @x >= 1; end\nend\n", ">=", ">")], [2])
    expect(one).to include("      changed line: e.rb:2\n")
  end

  it "prints no changed-line text outside diff mode or when the mutant touches no changed line" do
    source = "class K\n  def a; @x >= 1; end\nend\n"
    expect(render(edited(source, ">=", ">"))).not_to include("changed line")
    expect(render_scoped([edited(source, ">=", ">")], [9])).not_to include("changed line")
  end

  it "groups neighbouring mutants on a line only when their evidence matches as a set" do
    source = "class K\n  def a; @x >= 1 && @y <= 2; end\nend\n"
    tests = %w[./spec/a_spec.rb[1:1] ./spec/a_spec.rb[1:2]]
    sub = subjects_in(source, name: "e.rb").first
    same = [edited(source, ">=", ">", subject: sub, covered_by: tests),
            edited(source, "<=", "<", subject: sub, covered_by: tests.reverse)]
    expect(render(*same).scan("covered this line").size).to eq(1)
    other = [edited(source, ">=", ">", subject: sub, covered_by: tests),
             edited(source, "<=", "<", subject: sub, covered_by: tests.first(1))]
    expect(render(*other).scan("covered this line").size).to eq(2)
    dup = [edited(source, ">=", ">", subject: sub, covered_by: tests),
           edited(source, "<=", "<", subject: sub, covered_by: tests + tests.first(1))]
    expect(render(*dup).scan("covered this line").size).to eq(1)
    reused = [edited(source, ">=", ">", subject: sub, covered_by: tests),
              edited(source, "<=", "<", subject: sub, covered_by: tests, reused: true)]
    expect(render(*reused).scan("covered this line").size).to eq(2)
  end

  it "keeps mutants on one line apart when they touch different changed lines" do
    source = "class K\n  def a(x)\n    x +\n      1\n  end\nend\n"
    tests = %w[./spec/a_spec.rb[1:1]]
    sub = subjects_in(source, name: "e.rb").first
    a = edited(source, "+", "-", subject: sub, operator: "arithmetic", covered_by: tests)
    b = edited(source, "+\n      1", "0", subject: sub, operator: "test", covered_by: tests)
    text = render_scoped([a, b], [3, 4])
    expect(text.scan("covered this line").size).to eq(2)
    expect(text).to include("changed line: e.rb:3\n", "changed lines: e.rb:3, e.rb:4\n")
  end

  it "prints the hint text under its label, and no hint or caveat for an ignored survivor" do
    source = "class K\n  def a; @x >= 1; end\nend\n"
    text = render(edited(source, ">=", ">"))
    hint = Saboteur::Reporter::SurvivorHints.for("comparison")
    expect(text).to include("        hint: #{hint}\n")
    ignored = edited(source, ">=", ">")
    ignored.ignored = "equivalent"
    ignored_text = render(ignored)
    expect(ignored_text).not_to include("hint:")
    expect(ignored_text).not_to include("Hints are suggestions")
  end

  it "picks the coarse hint only for a coarse mutation of an operator without its own hint" do
    source = "class K\n  def a; @x >= 1; end\nend\n"
    coarse = render(edited(source, ">=", ">", operator: "zz_custom", coarse: true))
    expect(coarse).to include("        hint: #{Saboteur::Reporter::SurvivorHints::COARSE}\n")
    fine = render(edited(source, ">=", ">", operator: "zz_custom"))
    expect(fine).not_to include("hint:")
  end
end
