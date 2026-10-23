# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

# Golden pins for D1: a default run prints the findings list, expands the
# top SurvivorRanking picks (C2) as blocks, and closes with the dim closer.
D1_PINS_SOURCE = <<~RUBY
  class Alpha
    def one = 1 + 1
  end

  class Beta
    def four = 4 + 4
  end

  class Gamma
    def seven = 7 + 7
  end

  class Delta
    def ten = 10 + 10
  end

  class Epsilon
    def thirteen = 13 + 0
  end
RUBY

D1_THICK_COVERAGE = ["./spec/widget_spec.rb[2:1]", "./spec/widget_spec.rb[3:1]", "./spec/widget_spec.rb[4:1]"].freeze

RSpec.describe Saboteur::Reporter::DefaultFindings, "default findings pins" do
  # The goldens carry UTF-8 glyphs; pin the locale against C-locale CI legs.
  around do |example|
    saved = ENV.to_h.slice("LC_ALL", "LC_CTYPE", "LANG")
    ENV["LC_ALL"] = "C.UTF-8"
    example.run
  ensure
    keys = %w[LC_ALL LC_CTYPE LANG]
    keys.each { |key| saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key) }
  end

  after { FileUtils.rm_rf(@dir) if @dir }

  let(:out) { StringIO.new }
  let(:plain) { Saboteur::Reporter::Palette.new(enabled: false) }
  let(:coloured) { Saboteur::Reporter::Palette.new(enabled: true) }

  def dir = @dir ||= File.realpath(Dir.mktmpdir("saboteur-d1-pins-"))

  def subjects
    @subjects ||= begin
      path = File.join(dir, "widget.rb")
      File.write(path, D1_PINS_SOURCE)
      Saboteur::SubjectFinder.new.call(path).subjects
    end
  end

  # Alpha's thick coverage puts it last in the C2 ranking, not first.
  def survivor(id, covering: ["./spec/widget_spec.rb[2:1]"], replacement: "-", operator: "arithmetic",
               value_differed: nil)
    subject = subjects.find { |candidate| candidate.id == id } or raise "no subject #{id}"
    at = subject.file_source.index("+", subject.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 1,
                                              replacement:)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator:,
                                                      edits: [edit], coarse: false)
    Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                               mutated_source: subject.apply(mutation.edits), covered_by: covering,
                               value_differed:)
  end

  def four_survivors
    [survivor("Alpha#one", covering: D1_THICK_COVERAGE), survivor("Beta#four"), survivor("Gamma#seven"),
     survivor("Delta#ten")]
  end

  def render(results, palette: plain, diff_scope: nil, **options)
    out.truncate(0)
    out.rewind
    report = Saboteur::Report.new(results:, subjects: results.map(&:subject).uniq, wall_time: 1.0,
                                  root: dir, warnings: [], seed: 1, diff_scope:)
    ranked = Saboteur::Reporter::SurvivorRanking.ordered(report, results)
    described_class.new(out, palette, **options).call(report, ranked)
    out.string
  end

  it "names the digest of the mutant carrying the statement's label in the list (0.12.4 review, finding 1)" do
    no_change = survivor("Alpha#one", value_differed: false)
    changed = survivor("Alpha#one", replacement: "*", value_differed: true,
                                    covering: D1_THICK_COVERAGE)
    third = survivor("Alpha#one", replacement: "/", value_differed: true,
                                  covering: D1_THICK_COVERAGE + ["./spec/widget_spec.rb[5:1]"])
    text = render([no_change, changed, third])
    expect(text).to include("widget.rb:2 Alpha#one [assertion_gap] - #{changed.digest} (+2 more)")
    expect(text).not_to include("widget.rb:2 Alpha#one [assertion_gap] - #{no_change.digest}")
  end

  it "prints the list, the C2 top three blocks and the closer, monochrome" do
    expect(render(four_survivors)).to eq(<<~TEXT)
      widget.rb:6 Beta#four [number] - 525a515e7cf66814
      widget.rb:10 Gamma#seven [number] - 5ab92808752c1061
      widget.rb:14 Delta#ten [number] - 5504b9e836e5ded0
      widget.rb:2 Alpha#one [number] - 5644a11d15c37942

      Survivors (4) - changes your tests did not catch

      1. widget.rb:6 Beta#four [number · #1 of 4 blocks]
        the covering specs pass without pinning this number
      -   6 def four = 4 + 4
      +   6 def four = 4 - 4   arithmetic · 525a515e7cf66814
                         ^
        why it matters: the computed value can drift without a test noticing
        covered by ./spec/widget_spec.rb[2:1] - ran, still passed
        → try asserting the exact computed number

      2. widget.rb:10 Gamma#seven [number · #2 of 4 blocks]
        the covering specs pass without pinning this number
      -  10 def seven = 7 + 7
      +  10 def seven = 7 - 7   arithmetic · 5ab92808752c1061
                          ^
        why it matters: the computed value can drift without a test noticing
        covered by ./spec/widget_spec.rb[2:1] - ran, still passed
        → try asserting the exact computed number

      3. widget.rb:14 Delta#ten [number · #3 of 4 blocks]
        the covering specs pass without pinning this number
      -  14 def ten = 10 + 10
      +  14 def ten = 10 - 10   arithmetic · 5504b9e836e5ded0
                         ^
        why it matters: the computed value can drift without a test noticing
        covered by ./spec/widget_spec.rb[2:1] - ran, still passed
        → try asserting the exact computed number

      Hints are suggestions, not diagnoses: a survivor can also be an equivalent
      mutant, or a change the selected tests cannot observe.
      ... 1 more finding - saboteur survivors .saboteur/report.json,
      or re-run with --details

    TEXT
  end

  it "paints the header, blocks and closer under colour" do
    text = render(four_survivors, palette: coloured)
    expect(text).to include("\e[1mSurvivors (4) - changes your tests did not catch\e[0m")
    expect(text).to include("\e[1m1. widget.rb:6\e[0m")
    expect(text).to include("\e[2m... 1 more finding - saboteur survivors .saboteur/report.json,\n" \
                            "or re-run with --details\e[0m")
  end

  # Thin (Beta#four) and thick (Alpha#one) coverage, so both block shapes pin.
  it "expands every finding under --details, byte-for-byte the pre-D1 default" do
    text = render([survivor("Alpha#one", covering: D1_THICK_COVERAGE), survivor("Beta#four")], details: true)
    expect(text).to eq(<<~TEXT)
      Survivors (2) - changes your tests did not catch

      1. widget.rb:6 Beta#four [number · #1 of 2 blocks]
        the covering specs pass without pinning this number
      -   6 def four = 4 + 4
      +   6 def four = 4 - 4   arithmetic · 525a515e7cf66814
                         ^
        why it matters: the computed value can drift without a test noticing
        covered by ./spec/widget_spec.rb[2:1] - ran, still passed
        → try asserting the exact computed number

      2. widget.rb:2 Alpha#one [number · #2 of 2 blocks]
        the covering specs pass without pinning this number
      -   2 def one = 1 + 1
      +   2 def one = 1 - 1   arithmetic · 5644a11d15c37942
                        ^
        why it matters: the computed value can drift without a test noticing
        covered by ./spec/widget_spec.rb[2:1] - ran, still passed
        +2 more covered, all passed
        → try asserting the exact computed number

      Hints are suggestions, not diagnoses: a survivor can also be an equivalent
      mutant, or a change the selected tests cannot observe.

    TEXT
  end

  it "keeps a --since run fully expanded: every block, no list, no closer" do
    scope = Saboteur::Engine::DiffScope.new({ subjects.first.file => Set.new([2]) })
    text = render(four_survivors, diff_scope: scope)
    expect(text.scan(/#(\d+) of 4/).flatten).to eq((1..4).map(&:to_s))
    expect(text).not_to include("more finding")
    expect(text).not_to match(/^widget\.rb:\d+ Beta#four \[number\] - /)
  end

  it "expands everything and prints no closer with three or fewer findings" do
    text = render(four_survivors.first(3))
    expect(text.scan(/^widget\.rb:\d+ \w+#\w+ \[number\] - /).size).to eq(3)
    expect(text).to include("Survivors (3) - changes your tests did not catch")
    expect(text.scan(/^\d+\. widget\.rb:\d+ /).size).to eq(3)
    expect(text).not_to include("more finding")
  end
  it "keeps accepted-only reports on the full path: no list, no closer" do
    ignored = survivor("Beta#four")
    ignored.ignored = "not a real defect"
    text = render([ignored])
    expect(text).to include("Accepted (1, not scored):")
    expect(text).not_to include("more findings")
  end

  it "takes the full path, not the quiet list, when no survivor is live" do
    expect(render([])).to eq("")
  end

  it "suppresses the closer at exactly three findings" do
    three = [survivor("Beta#four"), survivor("Gamma#seven"), survivor("Delta#ten")]
    expect(render(three)).not_to include("more finding")
  end

  it "counts two unshown findings in the closer, pluralized" do
    five = four_survivors + [survivor("Epsilon#thirteen")]
    expect(render(five)).to include("... 2 more findings - saboteur survivors .saboteur/report.json,")
  end

  it "counts mutants, not statements, in the closer under --all-mutants" do
    four_mutants_three_statements = [survivor("Alpha#one"), survivor("Alpha#one", replacement: "*"),
                                     survivor("Beta#four"), survivor("Gamma#seven")]
    expect(render(four_mutants_three_statements, all_mutants: true)).to include("... 1 more finding -")
    expect(render(four_mutants_three_statements)).not_to include("more finding")
  end

  it "passes --all-mutants through to the details listing and closes with a blank line" do
    two_one_statement = [survivor("Alpha#one"), survivor("Alpha#one", replacement: "*")]
    text = render(two_one_statement, details: true, all_mutants: true)
    expect(text.scan(/\n\d+\. widget\.rb/).size).to eq(2)
    expect(text).to end_with("\n\n")
  end

  it "passes --all-mutants through to the top blocks" do
    two_one_statement = [survivor("Alpha#one"), survivor("Alpha#one", replacement: "*")]
    expect(render(two_one_statement, all_mutants: true).scan(/\n\s*\d+\. widget\.rb/).size).to eq(2)
    expect(render(two_one_statement).scan(/\n\s*\d+\. widget\.rb/).size).to eq(1)
  end

  it "prints no empty label bracket when a survivor has no classification" do
    allow(Saboteur::Reporter::SurvivorClassification).to receive(:label).and_return(nil)
    expect(render([survivor("Beta#four")])).to include("widget.rb:6 Beta#four - 525a515e7cf66814\n")
  end

  it "collapses sibling mutants on one statement into a (+1 more) count on the list line" do
    two = [survivor("Alpha#one"), survivor("Alpha#one", replacement: "*")]
    expect(render(two)).to match(/^widget\.rb:2 Alpha#one \[number\] - [0-9a-f]{16} \(\+1 more\)$/)
  end

  # Two files can define the same subject id; the list keys groups by
  # [path, line, subject_id] but SurvivorList blocks key by [subject.id, line],
  # so the closer's finding count and the block count are different units here.
  it "pins the mixed-unit case: same subject id and line in two files" do
    other_dir = dir
    other_path = File.join(other_dir, "other.rb")
    File.write(other_path, "class Alpha\n  def one = 1 + 1\nend\n")
    other_subject = Saboteur::SubjectFinder.new.call(other_path).subjects.find { |s| s.id == "Alpha#one" }
    at = other_subject.file_source.index("+", other_subject.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: other_subject.file, start_byte: at, end_byte: at + 1,
                                              replacement: "-")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: other_subject.id, operator: "arithmetic",
                                                      edits: [edit], coarse: false)
    twin = Saboteur::MutantResult.new(subject: other_subject, mutation:, status: :survived,
                                      mutated_source: other_subject.apply(mutation.edits),
                                      covered_by: ["./spec/other_spec.rb[2:1]"])

    results = [survivor("Alpha#one"), twin, survivor("Beta#four"), survivor("Gamma#seven")]
    text = render(results)

    # List: four lines, one per [path, line, subject_id] group.
    expect(text.scan(/^[\w.]+\.rb:\d+ \w+#\w+ \[number\] - /).size).to eq(4)
    expect(text).to include("widget.rb:2 Alpha#one")
    expect(text).to include("other.rb:2 Alpha#one")
    # Blocks: the two Alpha#one mutants at line 2 merge into one block, so
    # three blocks cover all four findings...
    expect(text.scan(/#\d+ of 3 blocks/).size).to eq(3)
    # ...yet the closer still subtracts 3 from the four list lines.
    expect(text).to include("... 1 more finding - saboteur survivors .saboteur/report.json,")
  end

  # A real map where every coverage line of the subject is recorded as hit
  # by each given test id (same shape as the SurvivorList pins).
  def map_for(subject, test_ids)
    file = Saboteur::Selection::CoverageMap.canonical(subject.file)
    lines = subject.coverage_lines.to_h { |line| [line, test_ids] }
    Saboteur::Selection::CoverageMap.new(lines: { file => lines }, tests: test_ids)
  end

  # Each kwarg is observable in only one scenario: a whole-suite spec the run
  # never loaded appears only when whole_suite_map is wired; a run map wider
  # than the covered-by union invents "(not run here)" when run_map is dropped
  # (the covered-by union is the fallback).
  it "threads the whole-suite and run maps through the limited block list" do
    beta = survivor("Beta#four")
    both = ["./spec/widget_spec.rb[2:1]", "./spec/flow_spec.rb[1:1]"]
    whole = map_for(beta.subject, both)

    text = render(four_survivors, whole_suite_map: whole,
                                  run_map: map_for(beta.subject, ["./spec/widget_spec.rb[2:1]"]))
    expect(text).to include("covered by 2 specs, incl. ./spec/flow_spec.rb[1:1] (not run here)")

    text = render(four_survivors, whole_suite_map: whole, run_map: map_for(beta.subject, both))
    expect(text).to include("covered by ./spec/widget_spec.rb[2:1] - ran, still passed")
    expect(text).not_to include("(not run here)")
    expect(text).not_to include("covering tests unknown")
  end

  it "threads the maps through the --details full path" do
    beta = survivor("Beta#four")
    both = ["./spec/widget_spec.rb[2:1]", "./spec/flow_spec.rb[1:1]"]
    whole = map_for(beta.subject, both)
    two = [survivor("Alpha#one", covering: D1_THICK_COVERAGE), beta]

    text = render(two, details: true, whole_suite_map: whole,
                       run_map: map_for(beta.subject, ["./spec/widget_spec.rb[2:1]"]))
    expect(text).to include("covered by 2 specs, incl. ./spec/flow_spec.rb[1:1] (not run here)")

    text = render(two, details: true, whole_suite_map: whole, run_map: map_for(beta.subject, both))
    expect(text).to include("covered by ./spec/widget_spec.rb[2:1] - ran, still passed")
    expect(text).not_to include("(not run here)")
    expect(text).not_to include("covering tests unknown")
  end

  it "takes the full path on a diff run even without --details" do
    scope = Saboteur::Engine::DiffScope.new({ subjects.first.file => Set.new([6]) })
    text = render([survivor("Beta#four")], diff_scope: scope)
    expect(text).to start_with("Survivors (1) - changes your tests did not catch\n")
    expect(text).to include("1. widget.rb:6 Beta#four [number · #1 of 1 block]")
  end

  it "takes the full path under --details even on a whole-project run" do
    text = render([survivor("Beta#four")], details: true)
    expect(text).to start_with("Survivors (1) - changes your tests did not catch\n")
  end
end
RSpec.describe Saboteur::Reporter::Terminal, "default findings wiring (D1)" do
  around do |example|
    saved = ENV.to_h.slice("LC_ALL", "LC_CTYPE", "LANG")
    ENV["LC_ALL"] = "C.UTF-8"
    example.run
  ensure
    keys = %w[LC_ALL LC_CTYPE LANG]
    keys.each { |key| saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key) }
  end

  after { FileUtils.rm_rf(@dirs.to_a) }

  def dir
    @dirs ||= []
    @dirs << (@dir ||= File.realpath(Dir.mktmpdir("saboteur-d1-wire-")))
    @dir
  end

  it "routes the default whole-project report through DefaultFindings" do
    source = <<~RUBY
      class Wired
        def a = 1 + 1
        def b = 2 + 2
        def c = 3 + 3
        def d = 4 + 4
      end
    RUBY
    path = File.join(dir, "wired.rb")
    File.write(path, source)
    subjects = Saboteur::SubjectFinder.new.call(path).subjects
    results = subjects.map do |subject|
      at = subject.file_source.index("+", subject.start_byte)
      edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 1,
                                                replacement: "-")
      mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "arithmetic",
                                                        edits: [edit], coarse: false)
      Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                 mutated_source: subject.apply(mutation.edits),
                                 covered_by: ["./spec/wired_spec.rb[2:1]"])
    end
    report = Saboteur::Report.new(results:, subjects:, wall_time: 1.0, root: dir, warnings: [], seed: 1)

    io = StringIO.new
    described_class.new(io).call(report)
    text = io.string
    expect(text).to include("... 1 more finding - saboteur survivors .saboteur/report.json,\n" \
                            "or re-run with --details")
    expect(text).to include("#3 of 4")
    expect(text).not_to include("#4 of 4")

    io = StringIO.new
    described_class.new(io, details: true).call(report)
    expect(io.string).to include("#4 of 4")
    expect(io.string).not_to include("more findings")
  end
  it "threads the whole-suite and run maps from Terminal through DefaultFindings" do
    path = File.join(dir, "wired.rb")
    File.write(path, "class Wired\n  def a = 1 + 1\nend\n")
    subject = Saboteur::SubjectFinder.new.call(path).subjects.find { |s| s.id == "Wired#a" }
    at = subject.file_source.index("+", subject.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 1,
                                              replacement: "-")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "arithmetic",
                                                      edits: [edit], coarse: false)
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits),
                                        covered_by: ["./spec/wired_spec.rb[2:1]"])
    report = Saboteur::Report.new(results: [result], subjects: [subject], wall_time: 1.0, root: dir,
                                  warnings: [], seed: 1)
    file = Saboteur::Selection::CoverageMap.canonical(subject.file)
    lines = subject.coverage_lines.to_h { |line| [line, ["./spec/wired_spec.rb[2:1]", "./spec/flow_spec.rb[1:1]"]] }
    whole = Saboteur::Selection::CoverageMap.new(lines: { file => lines },
                                                 tests: ["./spec/wired_spec.rb[2:1]", "./spec/flow_spec.rb[1:1]"])
    both = ["./spec/wired_spec.rb[2:1]", "./spec/flow_spec.rb[1:1]"]
    run_lines = subject.coverage_lines.to_h { |line| [line, both] }
    run = Saboteur::Selection::CoverageMap.new(lines: { file => run_lines }, tests: both)

    io = StringIO.new
    described_class.new(io, whole_suite_map: whole, run_map: run).call(report)
    expect(io.string).to include("covered by ./spec/wired_spec.rb[2:1] - ran, still passed")
    expect(io.string).not_to include("(not run here)")
    expect(io.string).not_to include("covering tests unknown")

    only_run = Saboteur::Selection::CoverageMap.new(
      lines: { file => subject.coverage_lines.to_h { |line| [line, ["./spec/wired_spec.rb[2:1]"]] } },
      tests: ["./spec/wired_spec.rb[2:1]"]
    )
    io = StringIO.new
    described_class.new(io, whole_suite_map: whole, run_map: only_run).call(report)
    expect(io.string).to include("covered by 2 specs, incl. ./spec/flow_spec.rb[1:1] (not run here)")
  end
end
