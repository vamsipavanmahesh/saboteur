# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

# Golden survivor blocks (DX wave 1): the finding is the code. Monochrome
# goldens pin the layout byte for byte; the colour pass pins the palette
# tokens on the structural rows.
PINS_CALCULATOR = "class Calculator\n  def compound(principal, rate, years)\n    " \
                  "principal * (1 + rate)**years\n  end\nend\n"

RSpec.describe Saboteur::Reporter::SurvivorList, "survivor blocks" do
  after { FileUtils.rm_rf(@dirs.to_a) }

  let(:out) { StringIO.new }
  let(:plain) { Saboteur::Reporter::Palette.new(enabled: false) }
  let(:coloured) { Saboteur::Reporter::Palette.new(enabled: true) }

  def dir
    @dirs ||= []
    @dirs << (@dir ||= File.realpath(Dir.mktmpdir("saboteur-pins-")))
    @dir
  end

  def subjects_in(source, name:, dir:)
    path = File.join(dir, name)
    File.write(path, source)
    Saboteur::SubjectFinder.new.call(path).subjects
  end

  def edited(source, from, to, operator:, dir:, name: "calculator.rb", coarse: false, **attributes)
    subject = subjects_in(source, name:, dir:).first
    at = subject.file_source.index(from, subject.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + from.size,
                                              replacement: to)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator:, edits: [edit],
                                                      coarse:)
    Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                               mutated_source: subject.apply(mutation.edits), **attributes)
  end

  def render(results, palette: plain)
    out.truncate(0)
    out.rewind
    root = File.dirname(results.first.subject.file)
    report = Saboteur::Report.new(results:, subjects: results.map(&:subject).uniq, wall_time: 1.0, root:,
                                  warnings: [], seed: 1)
    described_class.new(out, palette).call(report, results)
    out.string.dup
  end

  # The whole-suite lookup Terminal wires in production (review C1): real
  # CoverageMap objects, never doubles. run: nil means the report path
  # cannot say what ran, so only the covered_by union is known.
  def render_with_maps(results, whole:, run: nil, palette: plain)
    out.truncate(0)
    out.rewind
    root = File.dirname(results.first.subject.file)
    report = Saboteur::Report.new(results:, subjects: results.map(&:subject).uniq, wall_time: 1.0, root:,
                                  warnings: [], seed: 1)
    described_class.new(out, palette, whole_suite_map: whole, run_map: run).call(report, results)
    out.string.dup
  end

  # A real map where every coverage line of the subject is recorded as hit
  # by each given test id.
  def map_for(subject, test_ids)
    file = Saboteur::Selection::CoverageMap.canonical(subject.file)
    lines = subject.coverage_lines.to_h { |line| [line, test_ids] }
    Saboteur::Selection::CoverageMap.new(lines: { file => lines }, tests: test_ids)
  end

  let(:operand) do
    edited(PINS_CALCULATOR, "(1 + rate)**years", "years", operator: "operand_replacement", dir:,
                                                          covered_by: ["./spec/calculator_spec.rb[2:1]"])
  end

  it "renders the golden block, monochrome" do
    expect(render([operand])).to eq(<<~TEXT)
      Survivors (1) - changes your tests did not catch

      1. calculator.rb:3 Calculator#compound [result unchecked · #1 of 1 block]
        the covering specs pass without pinning this result
          2 def compound(principal, rate, years)
      -   3     principal * (1 + rate)**years
      +   3     principal * years   operand_replacement · b0f52efa7fd8afaa
                            ^^^^^
          4   end
        why it matters: the result no longer depends on the replaced operand
        covered by ./spec/calculator_spec.rb[2:1] - ran, still passed
    TEXT
  end

  it "labels a grouped statement from all its mutants, not the first (#P4)" do
    number = edited(PINS_CALCULATOR, "1 +", "2 +", operator: "literal_number", dir:,
                                                   covered_by: ["./spec/calculator_spec.rb[2:1]"])
    expect(Saboteur::Reporter::SurvivorClassification.label(number)).to eq("number")
    text = render([number, operand])
    expect(text).to include("1. calculator.rb:3 Calculator#compound [result unchecked · #1 of 1 block]")
    expect(text).to include("  the covering specs pass without pinning this result\n")
  end

  it "marks a group coarse by its first mutant, whatever the label comes from (#P4)" do
    whole = "principal * (1 + rate)**years"
    coarse = edited(PINS_CALCULATOR, whole, "nil", operator: "body_nil", dir:, coarse: true,
                                                   covered_by: ["./spec/calculator_spec.rb[2:1]"])
    expect(render([coarse, operand])).to include("[coarse · result unchecked · #1 of 1 block]")
    expect(render([operand, coarse])).to include("[result unchecked · #1 of 1 block]")
  end

  it "renders the golden block with colour tokens" do
    text = render([operand], palette: coloured)
    expect(text).to start_with("\e[1mSurvivors (1) - changes your tests did not catch\e[0m")
    expect(text).to include("\e[1m1. calculator.rb:3\e[0m")
    expect(text).to include("\e[31;1m-   3     principal * (1 + rate)**years\e[0m")
    expect(text).to include("\e[32m+   3     principal * years\e[0m\e[2m   operand_replacement")
    expect(text).to include("\e[32m#{' ' * 22}#{'^' * 5}\e[0m")
    expect(text).to include("\e[2m    2 def compound(principal, rate, years)\e[0m")
    expect(text).to include("  \e[2mwhy it matters: the result no longer depends on the replaced operand\e[0m")
  end

  it "aligns the span marker under the changed span of a comparison mutant" do
    result = edited(PINS_CALCULATOR, "**", "*", operator: "comparison", dir:)
    lines = render([result]).lines
    plus = lines.find { |line| line.start_with?("+") }
    marker = lines[lines.index(plus) + 1]
    expect(plus).to start_with("+   3     principal * (1 + rate)*years")
    expect(marker).to eq("#{' ' * 32}^\n")
  end

  it "aligns the span marker by characters, not bytes, on a multibyte line" do
    result = edited("class K\n  def a(n)\n    x = \"caf\u00e9 au lait\" + n.to_s\n  end\nend\n",
                    "+", "-", operator: "arithmetic", dir:, name: "k.rb")
    lines = render([result]).lines
    plus = lines.find { |line| line.start_with?("+") }
    marker = lines[lines.index(plus) + 1]
    expect(plus).to start_with("+   3     x = \"caf\u00e9 au lait\" - n.to_s")
    expect(marker).to eq("#{' ' * 29}^\n")
  end

  it "converts the byte offset to a character column when the line starts multibyte" do
    line = "\u00e9 + 2"
    offset = line.b.index("+")
    expect(described_class.new(out, plain).send(:char_span, line, [offset, 1])).to eq([2, 1])
  end

  it "prints only the - line when the mutant removes the statement" do
    result = edited("class K\n  def a\n    @x = 1\n    @x\n  end\nend\n", "@x = 1", "",
                    operator: "statement_removal", dir:, name: "k.rb")
    text = render([result])
    expect(text).to include("-   3     @x = 1\n")
    expect(text).not_to include("+   3")
    expect(text).not_to include("^^^")
  end

  it "caps a 30-line method at 10 rows with the middle elided and the changed line kept" do
    body = (1..27).map { |n| "    @v#{n} = #{n} >= #{n}\n" }.join
    source = "class K\n  def a\n#{body}    @v1\n  end\nend\n"
    subject = subjects_in(source, name: "long.rb", dir:).first
    at = subject.file_source.index(">= 14", subject.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 5,
                                              replacement: "> 14")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison", edits: [edit],
                                                      coarse: false)
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits))
    rows = render([result]).lines.grep(/\A[-+ ]+(\d+|\.{3})/)
    # 10 fence rows; the changed row renders as a -/+ pair.
    expect(rows.size).to eq(11)
    expect(rows.count { |line| line.include?("...") }).to eq(2)
    expect(rows.any? { |line| line.start_with?("-") && line.include?("@v14 = 14 >= 14") }).to be(true)
    expect(rows.first).to include("def a")
    expect(rows.last).to include("end")
  end

  it "collapses sibling mutants on the statement to one block plus a digest line and an expand command" do
    sibling = edited(PINS_CALCULATOR, "* (1 + rate)", "/ (1 + rate)", operator: "arithmetic", dir:)
    text = render([operand, sibling])
    expect(text.scan(/^- /).size).to eq(1)
    expect(text).to include("  1 more mutant here: #{sibling.digest} (arithmetic)\n")
    expect(text).to include("       expand: saboteur run --all-mutants\n")
  end

  it "echoes the run's diff scope in the expand command, shell-escaped" do
    result = edited(PINS_CALCULATOR, "**", "*", operator: "comparison", dir:)
    sibling = edited(PINS_CALCULATOR, "* (1 + rate)", "/ (1 + rate)", operator: "arithmetic", dir:)
    subject = result.subject
    scope = Saboteur::Engine::DiffScope.new(subject.file => Set[3])
    out = StringIO.new
    report = Saboteur::Report.new(results: [result, sibling], subjects: [subject], wall_time: 1.0,
                                  root: dir, warnings: [], seed: 1, diff_scope: scope, since: "HEAD~3")
    Saboteur::Reporter::SurvivorList.new(out, plain).call(report, [result, sibling])
    expect(out.string).to include("       expand: saboteur run --all-mutants --since HEAD\\~3\n")
  end

  it "widens the expand to the whole project only when the run recorded no ref" do
    result = edited(PINS_CALCULATOR, "**", "*", operator: "comparison", dir:)
    sibling = edited(PINS_CALCULATOR, "* (1 + rate)", "/ (1 + rate)", operator: "arithmetic", dir:)
    subject = result.subject
    scope = Saboteur::Engine::DiffScope.new(subject.file => Set[3])
    out = StringIO.new
    report = Saboteur::Report.new(results: [result, sibling], subjects: [subject], wall_time: 1.0,
                                  root: dir, warnings: [], seed: 1, diff_scope: scope)
    Saboteur::Reporter::SurvivorList.new(out, plain).call(report, [result, sibling])
    expect(out.string).to include("       expand: saboteur run --all-mutants\n")
    expect(out.string).not_to include("--since")
  end

  it "keeps the expand whole-project for a non-diff run that happens to know a ref" do
    result = edited(PINS_CALCULATOR, "**", "*", operator: "comparison", dir:)
    sibling = edited(PINS_CALCULATOR, "* (1 + rate)", "/ (1 + rate)", operator: "arithmetic", dir:)
    subject = result.subject
    out = StringIO.new
    report = Saboteur::Report.new(results: [result, sibling], subjects: [subject], wall_time: 1.0,
                                  root: dir, warnings: [], seed: 1, since: "HEAD~3")
    Saboteur::Reporter::SurvivorList.new(out, plain).call(report, [result, sibling])
    expect(out.string).to include("       expand: saboteur run --all-mutants\n")
    expect(out.string).not_to include("--since")
  end

  it "prints one quoted dim line per accepted survivor, marked not scored" do
    accepted = edited("class Cart\n  def total; @items.sum.round(2); end\nend\n", ".round(2)", "",
                      operator: "chain_removal", dir:, name: "cart.rb")
    accepted.ignored = "display-only rounding"
    text = render([operand, accepted])
    expect(text).to include(%(Accepted (1, not scored): cart.rb:2 chain_removal - "display-only rounding"\n))
    expect(text).not_to include("cart.rb:2 Cart#total")
  end

  it "marks an incremental survivor's covering tests as passed in an earlier run" do
    reused = edited(PINS_CALCULATOR, "**", "*", operator: "comparison", dir:, covered_by: ["./spec/c_spec.rb[1:1]"],
                                                reused: true)
    expect(render([reused])).to include("covered by ./spec/c_spec.rb[1:1] - passed in an earlier run (--incremental)")
  end

  describe "the +N more covered line" do
    def covered_result(**attributes)
      covered = ["./spec/c_spec.rb[1:1]", "./spec/c_spec.rb[1:2]", "./spec/c_spec.rb[1:3]"]
      edited(PINS_CALCULATOR, "**", "*", operator: "comparison", dir:, covered_by: covered, **attributes)
    end

    it "names the tests that ran when every covering test ran" do
      result = covered_result(executed: ["./spec/c_spec.rb[1:1]", "./spec/c_spec.rb[1:2]",
                                         "./spec/c_spec.rb[1:3]"])
      expect(render([result])).to include("\n  +2 more covered (all 2 ran, all passed)\n")
    end

    it "says none ran when the run executed none of the covering tests" do
      result = covered_result(executed: [])
      expect(render([result])).to include("\n  +2 more covered (none ran this run)\n")
    end

    it "names the ran and not-run counts when some covering tests ran" do
      covered = ["./spec/c_spec.rb[1:1]", "./spec/c_spec.rb[1:2]",
                 "./spec/c_spec.rb[1:3]", "./spec/c_spec.rb[1:4]"]
      result = edited(PINS_CALCULATOR, "**", "*",
                      operator: "comparison", dir:, covered_by: covered,
                      executed: ["./spec/c_spec.rb[1:1]", "./spec/c_spec.rb[1:2]"])
      expect(render([result])).to include("\n  +3 more covered (1 ran, all passed; 2 did not run this run)\n")
    end

    it "names none-ran over the bare verdict when a sibling recorded an empty executed set" do
      pair = ["./spec/c_spec.rb[1:1]", "./spec/c_spec.rb[1:2]"]
      unknown = edited(PINS_CALCULATOR, "**", "*",
                       operator: "comparison", dir:, covered_by: pair)
      recorded_none = edited(PINS_CALCULATOR, "* (1 + rate)", "/ (1 + rate)",
                             operator: "arithmetic", dir:, covered_by: pair, executed: [])
      expect(render([unknown, recorded_none])).to include("\n  +1 more covered (none ran this run)\n")
    end

    it "says none ran when the recorded run executed none of the other covering tests" do
      result = covered_result(executed: ["./spec/c_spec.rb[1:1]"])
      expect(render([result])).to include("\n  +2 more covered (none ran this run)\n")
    end

    it "keeps the bare verdict when the run did not record which tests ran" do
      result = covered_result(executed: nil)
      expect(render([result])).to include("\n  +2 more covered, all passed\n")
    end
  end

  describe "hint gating" do
    it "prints the operator hint for a gap-labeled survivor, with the caveat" do
      result = edited(PINS_CALCULATOR, "1 + rate", "1 - rate", operator: "arithmetic", dir:)
      text = render([result])
      expect(text).to include("\n  → try asserting the exact computed number\n")
      expect(text).to include("\n\nHints are suggestions, not diagnoses:")
    end

    it "never hints a likely_equivalent survivor" do
      allow(Saboteur::Reporter::SurvivorClassification).to receive(:label).and_return("likely_equivalent")
      result = edited(PINS_CALCULATOR, "1 + rate", "1 - rate", operator: "arithmetic", dir:)
      text = render([result])
      expect(text).not_to include("→")
      expect(text).not_to include("Hints are suggestions")
      expect(text).to include("[likely_equivalent · #1 of 1 block]\n  " \
                              "compiles to the same instructions as the original")
    end
  end

  it "prints nothing when there are no survivors" do
    report = Saboteur::Report.new(results: [], subjects: [], wall_time: 1.0, root: dir, warnings: [], seed: 1)
    described_class.new(out, plain).call(report, [])
    expect(out.string).to eq("")
  end

  it "numbers blocks across subjects and never merges same-line survivors from different subjects" do
    other = edited("class K\n  def a\n    @x = 1 + 2\n    @x\n  end\nend\n", "1 + 2", "1 - 2",
                   operator: "arithmetic", dir:, name: "k.rb")
    text = render([operand, other])
    expect(text).to include("1. calculator.rb:3 Calculator#compound", "2. k.rb:3 K#a")
  end

  it "marks a coarse whole-method survivor so the block does not read as pinpoint" do
    allow(Saboteur::Reporter::SurvivorClassification).to receive(:label).and_return(nil)
    whole = edited(PINS_CALCULATOR, "principal * (1 + rate)**years", "nil", operator: "body_nil", dir:,
                                                                            coarse: true)
    expect(render([whole])).to include("1. calculator.rb:3 Calculator#compound [coarse · #1 of 1 block]
")
  end

  it "counts blocks, not mutants, in the rank suffix and says which" do
    allow(Saboteur::Reporter::SurvivorClassification).to receive(:label).and_return(nil)
    sibling = edited(PINS_CALCULATOR, "* (1 + rate)", "/ (1 + rate)", operator: "arithmetic", dir:)
    other = edited("class K\n  def a\n    @x = 1 + 2\n    @x\n  end\nend\n", "1 + 2", "1 - 2",
                   operator: "arithmetic", dir:, name: "k.rb")
    text = render([operand, sibling, other])
    expect(text).to include("Survivors (3) - ",
                            "1. calculator.rb:3 Calculator#compound [#1 of 2 blocks]",
                            "2. k.rb:3 K#a [#2 of 2 blocks]")
  end

  it "pins the bare rank suffix when the survivor has no label" do
    allow(Saboteur::Reporter::SurvivorClassification).to receive(:label).and_return(nil)
    expect(render([operand])).to include("1. calculator.rb:3 Calculator#compound [#1 of 1 block]\n")
  end

  it "renders every row of a small method and a 10-line method with no elision" do
    body8 = (1..6).map { |n| "    @v#{n} = #{n}\n" }.join
    at8 = edited("class K\n  def a\n#{body8}    @v1\n  end\nend\n", "@v3 = 3", "@v3 = 4",
                 operator: "literal_number", dir:, name: "k8.rb")
    rows8 = render([at8]).lines.grep(/\A[-+ ]+\d/)
    expect(rows8.size).to eq(10) # 9 source lines with the changed row as a -/+ pair
    expect(render([at8])).not_to include("...")

    body10 = (1..7).map { |n| "    @v#{n} = #{n}\n" }.join
    at10 = edited("class K\n  def a\n#{body10}    @v1\n  end\nend\n", "@v5 = 5", "@v5 = 6",
                  operator: "literal_number", dir:, name: "k10.rb")
    text10 = render([at10])
    expect(text10.lines.grep(/\A[-+ ]+\d/).size).to eq(11)
    expect(text10).not_to include("...")
  end

  it "applies several edits on one line in reverse byte order" do
    source = "class K\n  def a\n    1 >= 1 ? 1 : 2\n  end\nend\n"
    subject = subjects_in(source, name: "k.rb", dir:).first
    from = subject.file_source.index(">=")
    edits = [Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: from, end_byte: from + 2,
                                                replacement: ">"),
             Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: from + 3, end_byte: from + 4,
                                                replacement: "2")]
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison", edits:,
                                                      coarse: false)
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits))
    text = render([result])
    expect(text).to include("+   3     1 > 2 ? 1 : 2", "\n            ^^\n")
  end

  it "caps sibling digests at three and counts the rest" do
    siblings = [["* (1 + rate)", "/ (1 + rate)", "arithmetic"], ["**", "*", "operand_replacement"],
                ["1 + rate", "1 - rate", "arithmetic"], ["years\n", "1\n", "literal_number"]].map do |from, to, op|
      edited(PINS_CALCULATOR, from, to, operator: op, dir:)
    end
    text = render([operand, *siblings])
    expect(text).to include("  4 more mutants here: ")
    expect(text).to match(/4 more mutants here: [0-9a-f]+ \(\w+\), [0-9a-f]+ \(\w+\), [0-9a-f]+ \(\w+\) \(\+1 more\)/)
  end

  it "separates the accepted section with a blank line and lists several accepted one per line" do
    accepted = edited("class Cart\n  def total; @items.sum.round(2); end\nend\n", ".round(2)", "",
                      operator: "chain_removal", dir:, name: "cart.rb")
    accepted.ignored = "display-only rounding"
    second = edited("class Cart\n  def total; @items.sum.round(2); end\nend\n", ".sum", ".size",
                    operator: "method_swap", dir:, name: "cart.rb")
    second.ignored = "close enough"
    text = render([accepted])
    expect(text).to match(/\n\nAccepted \(1, not scored\): cart\.rb:2 chain_removal - "display-only rounding"\n\z/)
    text = render([accepted, second])
    expect(text).to include("Accepted (2, not scored):\n")
    expect(text).to include("  cart.rb:2 chain_removal - \"display-only rounding\"\n",
                            "  cart.rb:2 method_swap - \"close enough\"\n")
  end

  it "aligns the elision marker under the gutter" do
    body = (1..27).map { |n| "    @v#{n} = #{n}\n" }.join
    result = edited("class K\n  def a\n#{body}    @v1\n  end\nend\n", "@v14 = 14", "@v14 = 15",
                    operator: "literal_number", dir:, name: "k.rb")
    rows = render([result]).lines.select { |line| line.include?("...") }
    expect(rows).to eq(["      ...\n", "      ...\n"])
  end

  it "drops out-of-range fence rows exactly at the first and last line" do
    body = (1..10).map { |n| "    @v#{n} = #{n}\n" }.join
    def_edit = edited("class K\n  def a\n#{body}  end\nend\n", "def a", "def b",
                      operator: "literal_string", dir:, name: "k.rb")
    rows = render([def_edit]).lines.grep(/\A[-+ ]+(\d|\.\.\.)/)
    expect(rows.first).to start_with("-   2 ")
    expect(rows.grep(/\A +\d/).size).to eq(4)

    tail_edit = edited("class K\n  def a\n#{body}  end\nend\n", "  end", "  end # done",
                       operator: "literal_string", dir:, name: "k.rb")
    text = render([tail_edit])
    expect(text).to include("+  13   end # done")
  end

  it "elides exactly one skipped row between kept rows" do
    body = (1..10).map { |n| "    @v#{n} = #{n}\n" }.join
    result = edited("class K\n  def a\n#{body}  end\nend\n", "@v5 = 5", "@v5 = 6",
                    operator: "literal_number", dir:, name: "k.rb")
    text = render([result])
    expect(text.scan(/^ {6}\.\.\.\n/).size).to eq(2)
    expect(text).not_to include("@v3")
    expect(text).to include("@v4 = 4", "@v5 = 6", "@v6 = 6")
  end

  it "attributes the covering-test phrase to the group member that owns the test" do
    source = "class K\n  def a\n    1 >= 1\n  end\nend\n"
    reused = edited(source, ">=", ">", operator: "comparison", dir:, name: "k.rb",
                                       covered_by: ["./spec/a_spec.rb[1:1]"], reused: true)
    fresh = edited(source, ">=", "<=", operator: "comparison", dir:, name: "k.rb",
                                       covered_by: ["./spec/b_spec.rb[1:1]"])
    text = render([fresh, reused])
    expect(text).to include("  covered by ./spec/b_spec.rb[1:1] ")
    expect(text).to include("- ran, still passed")
    expect(text).not_to include("- passed in an earlier run")

    uncovered = edited(source, ">=", "!=", operator: "comparison", dir:, name: "k.rb")
    text = render([uncovered, reused])
    expect(text).to include("  covered by ./spec/a_spec.rb[1:1] ")
    expect(text).to include("- passed in an earlier run (--incremental)")
  end

  # Review C1: scoped runs narrow their own map to the specs they loaded, so
  # survivor presentation consults the cached whole-suite map.
  describe "whole-suite covering map" do
    let(:calculator_id) { "./spec/calculator_spec.rb[2:1]" }
    let(:flow_id) { "./spec/flow_spec.rb[1:1]" }
    let(:survivor) do
      edited(PINS_CALCULATOR, "1 + rate", "1 - rate", operator: "comparison", dir:,
                                                      covered_by: [calculator_id])
    end

    it "says covering tests are unknown when no whole-suite map exists, with no bare covered-by" do
      text = render_with_maps([survivor], whole: nil, run: map_for(survivor.subject, [calculator_id]))

      expect(text).to include("covering tests unknown - run a full coverage build")
      expect(text).not_to include("covered by")
    end

    it "names whole-suite covering specs the run never loaded, and marks an exact-line pin" do
      whole = map_for(survivor.subject, [calculator_id, flow_id])
      run = map_for(survivor.subject, [calculator_id])
      text = render_with_maps([survivor], whole:, run:)

      expect(text).to include("covered by 2 specs, incl. ./spec/flow_spec.rb[1:1] (not run here)")
      expect(text).to include("likely covered elsewhere: ./spec/flow_spec.rb[1:1] pins this line (not run here)")
    end

    it "counts only the run map's tests as run, not the covered-by union" do
      outside = edited(PINS_CALCULATOR, "1 + rate", "1 - rate", operator: "comparison", dir:,
                                                                covered_by: ["./spec/outside_spec.rb[1:1]"])
      whole = map_for(outside.subject, [calculator_id, flow_id])
      run = map_for(outside.subject, [calculator_id])
      text = render_with_maps([outside], whole:, run:)

      expect(text).to include("covered by 2 specs, incl. ./spec/flow_spec.rb[1:1] (not run here)")
    end

    it "falls back to the covered-by union when the run kept no map" do
      whole = map_for(survivor.subject, [calculator_id, flow_id])
      text = render_with_maps([survivor], whole:, run: nil)

      expect(text).to include("covered by 2 specs, incl. ./spec/flow_spec.rb[1:1] (not run here)")
    end

    it "names the first of several covering specs the run never loaded" do
      extra_id = "./spec/extra_spec.rb[1:1]"
      whole = map_for(survivor.subject, [calculator_id, flow_id, extra_id])
      run = map_for(survivor.subject, [calculator_id])
      text = render_with_maps([survivor], whole:, run:)

      expect(text).to include("covered by 3 specs, incl. ./spec/flow_spec.rb[1:1] (not run here)")
      expect(text).to include("likely covered elsewhere: ./spec/flow_spec.rb[1:1] pins this line (not run here)")
    end

    it "skips the exact-line pin when no whole-suite spec pins the mutant's line" do
      subject = survivor.subject
      edit_lines = survivor.mutation.edits.flat_map { |edit| subject.coverage_lines_for(edit) }
      other_lines = subject.coverage_lines - edit_lines
      file = Saboteur::Selection::CoverageMap.canonical(subject.file)
      whole = Saboteur::Selection::CoverageMap.new(
        lines: { file => other_lines.to_h { |line| [line, [flow_id]] } }, tests: [flow_id]
      )
      run = map_for(subject, [calculator_id])
      text = render_with_maps([survivor], whole:, run:)

      expect(text).to include("covered by 1 spec, incl. ./spec/flow_spec.rb[1:1] (not run here)")
      expect(text).not_to include("likely covered elsewhere")
    end

    it "takes the exact-line pin from the block's first mutant, not a multiline sibling" do
      alpha_id = "./spec/alpha_spec.rb[1:1]"
      source = "class Calculator\n  def compound(amount, rate, years)\n    amount *\n      " \
               "(1 + rate)**years\n  end\nend\n"
      narrow = edited(source, "amount *", "amount /", operator: "arithmetic", dir:,
                                                      covered_by: [calculator_id])
      wide = edited(source, "amount *\n      (1 + rate)**years", "nil", operator: "statement_removal", dir:,
                                                                        covered_by: [calculator_id])
      subject = narrow.subject
      file = Saboteur::Selection::CoverageMap.canonical(subject.file)
      whole = Saboteur::Selection::CoverageMap.new(
        lines: { file => { 3 => [calculator_id, flow_id], 4 => [calculator_id, alpha_id] } },
        tests: [calculator_id, alpha_id, flow_id]
      )
      run = Saboteur::Selection::CoverageMap.new(lines: { file => { 3 => [calculator_id], 4 => [calculator_id] } },
                                                 tests: [calculator_id])
      text = render_with_maps([narrow, wide], whole:, run:)

      expect(text).to include("covered by 3 specs, incl. ./spec/alpha_spec.rb[1:1] (not run here)")
      expect(text).to include("likely covered elsewhere: ./spec/flow_spec.rb[1:1] pins this line (not run here)")
    end

    it "is byte-identical to the legacy block when the run map IS the whole-suite map" do
      map = map_for(survivor.subject, [calculator_id])

      expect(render_with_maps([survivor], whole: map, run: map)).to eq(render([survivor]))
    end

    it "keeps the legacy block when the whole-suite lookup is not wired" do
      expect(render([survivor])).to include("  covered by ./spec/calculator_spec.rb[2:1] ")
    end
  end

  it "prints the hint caveat only for hints on survivors the limit actually showed" do
    shown = edited(PINS_CALCULATOR, "1 + rate", "1 - rate", operator: "arithmetic", dir:)
    hidden = edited("class K\n  def a\n    @x = 1 + 2\n    @x\n  end\nend\n", "1 + 2", "1 - 2",
                    operator: "arithmetic", dir:, name: "k.rb")
    allow(Saboteur::Reporter::SurvivorClassification).to receive(:label) do |result|
      result.equal?(shown) ? "likely_equivalent" : "missing_test"
    end
    limited = StringIO.new
    report = Saboteur::Report.new(results: [shown, hidden], subjects: [shown.subject, hidden.subject],
                                  wall_time: 1.0, root: File.dirname(shown.subject.file), warnings: [],
                                  seed: 1)
    described_class.new(limited, plain, limit: 1).call(report, [shown, hidden])
    expect(limited.string).to include("Survivors (2) - changes your tests did not catch")
    expect(limited.string).not_to include("2. k.rb")
    expect(limited.string).not_to include("Hints are suggestions")
  end

  it "prints no reason line when the survivor has no label" do
    allow(Saboteur::Reporter::SurvivorClassification).to receive(:label).and_return(nil)
    expect(render([operand])).not_to match(/^ +$/)
  end

  describe "#wrap boundaries" do
    def wrap(text, width)
      described_class.new(out, plain).send(:wrap, text, width)
    end

    it "keeps a word that fits the width exactly, space included" do
      expect(wrap("aaaa bbbb", 9)).to eq("aaaa bbbb")
    end

    it "wraps when the joining space itself overflows the width" do
      expect(wrap("aaaa bbbb", 8)).to eq("aaaa\nbbbb")
    end

    it "wraps a short word after a long line and a long word after a short line" do
      expect(wrap("aaaaa b", 6)).to eq("aaaaa\nb")
      expect(wrap("a bbbbb", 6)).to eq("a\nbbbbb")
    end

    it "appends to the current line across several wraps" do
      expect(wrap("aaaa b c d", 4)).to eq("aaaa\nb c\nd")
    end
  end
end
