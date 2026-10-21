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
  def survivor(id, covering: ["./spec/widget_spec.rb[2:1]"])
    subject = subjects.find { |candidate| candidate.id == id } or raise "no subject #{id}"
    at = subject.file_source.index("+", subject.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 1,
                                              replacement: "-")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "arithmetic",
                                                      edits: [edit], coarse: false)
    Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                               mutated_source: subject.apply(mutation.edits), covered_by: covering)
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

  it "prints the list, the C2 top three blocks and the closer, monochrome" do
    expect(render(four_survivors)).to eq(<<~TEXT)
      widget.rb:6 Beta#four [missing_test] - 525a515e7cf66814
      widget.rb:10 Gamma#seven [missing_test] - 5ab92808752c1061
      widget.rb:14 Delta#ten [missing_test] - 5504b9e836e5ded0
      widget.rb:2 Alpha#one [missing_test] - 5644a11d15c37942

      Survivors (4) - changes your tests did not catch

      1. widget.rb:6 Beta#four [missing_test · #1 of 4: the covering specs pass without pinning this change]
      -   6 def four = 4 + 4
      +   6 def four = 4 - 4   arithmetic · 525a515e7cf66814
                         ^
        why it matters: the computed value can drift without a test noticing
        covered by ./spec/widget_spec.rb[2:1] - ran, still passed
        → try asserting the exact computed number

      2. widget.rb:10 Gamma#seven [missing_test · #2 of 4: the covering specs pass without pinning this change]
      -  10 def seven = 7 + 7
      +  10 def seven = 7 - 7   arithmetic · 5ab92808752c1061
                          ^
        why it matters: the computed value can drift without a test noticing
        covered by ./spec/widget_spec.rb[2:1] - ran, still passed
        → try asserting the exact computed number

      3. widget.rb:14 Delta#ten [missing_test · #3 of 4: the covering specs pass without pinning this change]
      -  14 def ten = 10 + 10
      +  14 def ten = 10 - 10   arithmetic · 5504b9e836e5ded0
                         ^
        why it matters: the computed value can drift without a test noticing
        covered by ./spec/widget_spec.rb[2:1] - ran, still passed
        → try asserting the exact computed number

      Hints are suggestions, not diagnoses: a survivor can also be an equivalent mutant, or a change the selected tests cannot observe.
      ... 1 more finding - saboteur survivors .saboteur/report.json, or re-run with --details

    TEXT
  end

  it "paints the header, blocks and closer under colour" do
    text = render(four_survivors, palette: coloured)
    expect(text).to include("\e[1mSurvivors (4) - changes your tests did not catch\e[0m")
    expect(text).to include("\e[1m1. widget.rb:6\e[0m")
    expect(text).to include("\e[2m... 1 more finding - saboteur survivors .saboteur/report.json, " \
                            "or re-run with --details\e[0m")
  end

  # Thin (Beta#four) and thick (Alpha#one) coverage, so both block shapes pin.
  it "expands every finding under --details, byte-for-byte the pre-D1 default" do
    text = render([survivor("Alpha#one", covering: D1_THICK_COVERAGE), survivor("Beta#four")], details: true)
    expect(text).to eq(<<~TEXT)
      Survivors (2) - changes your tests did not catch

      1. widget.rb:6 Beta#four [missing_test · #1 of 2: the covering specs pass without pinning this change]
      -   6 def four = 4 + 4
      +   6 def four = 4 - 4   arithmetic · 525a515e7cf66814
                         ^
        why it matters: the computed value can drift without a test noticing
        covered by ./spec/widget_spec.rb[2:1] - ran, still passed
        → try asserting the exact computed number

      2. widget.rb:2 Alpha#one [missing_test · #2 of 2: the covering specs pass without pinning this change]
      -   2 def one = 1 + 1
      +   2 def one = 1 - 1   arithmetic · 5644a11d15c37942
                        ^
        why it matters: the computed value can drift without a test noticing
        covered by ./spec/widget_spec.rb[2:1] - ran, still passed
        +2 more covered, all passed
        → try asserting the exact computed number

      Hints are suggestions, not diagnoses: a survivor can also be an equivalent mutant, or a change the selected tests cannot observe.

    TEXT
  end

  it "keeps a --since run fully expanded: every block, no list, no closer" do
    scope = Saboteur::Engine::DiffScope.new({ subjects.first.file => Set.new([2]) })
    text = render(four_survivors, diff_scope: scope)
    expect(text.scan(/#(\d+) of 4/).flatten).to eq((1..4).map(&:to_s))
    expect(text).not_to include("more finding")
    expect(text).not_to match(/^widget\.rb:\d+ Beta#four \[missing_test\] - /)
  end

  it "expands everything and prints no closer with three or fewer findings" do
    text = render(four_survivors.first(3))
    expect(text.scan(/^widget\.rb:\d+ \w+#\w+ \[missing_test\] - /).size).to eq(3)
    expect(text).to include("Survivors (3) - changes your tests did not catch")
    expect(text.scan(/^\d+\. widget\.rb:\d+ /).size).to eq(3)
    expect(text).not_to include("more finding")
  end
end
