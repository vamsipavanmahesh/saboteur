# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Golden pins for PR6's --quiet text report: one line per finding (each
# surviving statement, every untested subject), then the canonical summary
# and verdict lines verbatim, and nothing else. --quiet is a filter over the
# same rendered report, not a fourth format.
RSpec.describe Saboteur::Reporter::Terminal, "quiet pins" do
  # The goldens carry UTF-8 glyphs; pin the locale so a C-locale CI leg does
  # not downgrade them to their ASCII fallbacks.
  around do |example|
    saved = ENV.to_h.slice("LC_ALL", "LC_CTYPE", "LANG")
    ENV["LC_ALL"] = "C.UTF-8"
    example.run
  ensure
    keys = %w[LC_ALL LC_CTYPE LANG]
    keys.each { |key| saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key) }
  end

  def render(report, **options)
    io = StringIO.new
    described_class.new(io, **options).call(report)
    io.string
  end

  def source
    <<~RUBY
      class Calculator
        def compound(principal, rate, years)
          principal * (1 + rate)**years
        end
      end

      class Cart
        def total
          0
        end
      end
    RUBY
  end

  def subjects
    @subjects ||= subjects_in(source, name: "calculator.rb")
  end

  def calculator = subjects.find { |subject| subject.id == "Calculator#compound" }
  def cart = subjects.find { |subject| subject.id == "Cart#total" }

  def result(status, original, replacement, covered_by: ["spec/calculator_spec.rb:7"])
    at = calculator.file_source.index(original)
    edit = Saboteur::MutationSource::Edit.new(file: calculator.file, start_byte: at,
                                              end_byte: at + original.bytesize, replacement:)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: calculator.id, operator: "comparison",
                                                      edits: [edit])
    Saboteur::MutantResult.new(subject: calculator, mutation:, status:,
                               mutated_source: calculator.apply(mutation.edits), covered_by:)
  end

  # Three survivors on one statement (line 3): the quiet line names the
  # first digest and collapses the rest as "(+2 more)".
  let(:survivors) { [result(:survived, "*", "/"), result(:survived, "**", "*"), result(:survived, "+", "-")] }
  let(:killed) { result(:killed, "1", "0", covered_by: ["spec/calculator_spec.rb:9"]) }
  let(:report) do
    Saboteur::Report.new(results: [killed, *survivors], subjects:, wall_time: 62,
                         root: File.dirname(calculator.file), seed: 1,
                         skipped_subjects: { cart => Saboteur::Reporter::ScoreTable::NO_COVERAGE })
  end
  let(:first_digest) do
    Saboteur::Reporter::SurvivorRanking.ordered(report, report.unignored_survivors).first.digest
  end

  it "prints the golden four lines in monochrome: findings, summary, verdict, nothing else" do
    text = render(report, exit_code: 1, threshold: 80, quiet: true)
    expect(text).to eq(<<~TEXT)
      calculator.rb:3 Calculator#compound [missing_test] - #{first_digest} (+2 more)
      calculator.rb:8 Cart#total [untested]
      saboteur: 1 killed, 3 survived, 1 subject untested in 1m02s - score 25.0% (threshold 80)
      ✗ exit 1 - score 25.0% below threshold 80, 3 survivors
    TEXT
  end

  it "prints the same lines under colour, with only the summary and verdict paints" do
    text = render(report, exit_code: 1, threshold: 80, quiet: true, color: :always)
    expect(text).to eq(<<~TEXT)
      calculator.rb:3 Calculator#compound [missing_test] - #{first_digest} (+2 more)
      calculator.rb:8 Cart#total [untested]
      saboteur: \e[32m1 killed\e[0m, \e[31;1m3 survived\e[0m, 1 subject untested in 1m02s - score \e[31;1m25.0%\e[0m (threshold 80)
      \e[31;1m✗ exit 1 - score 25.0% below threshold 80, 3 survivors\e[0m
    TEXT
  end

  it "prints no source context, score table, tally or next steps" do
    text = render(report, exit_code: 1, threshold: 80, quiet: true)
    expect(text).not_to include("Survivors (", "principal * (1 + rate)**years", "Score:",
                                "covered this line", "saboteur #{Saboteur::VERSION}", "next:")
  end

  it "consumes the same findings as the default report: same digests and subjects, different lines out" do
    quiet = render(report, exit_code: 1, threshold: 80, quiet: true)
    default = render(report, exit_code: 1, threshold: 80)
    survivors.each { |survivor| expect(default).to include(survivor.digest) }
    # The quiet line shows the same first digest the default block lists and
    # collapses the other two of the group it names.
    expect(quiet).to include("#{first_digest} (+2 more)")
    expect(default).to include(first_digest)
    %w[Calculator#compound Cart#total].each do |id|
      expect(quiet).to include(id)
      expect(default).to include(id)
    end
    expect(default).to include("Survivors (3):")
    expect(quiet).not_to include("Survivors (3):")
  end

  it "prints no collapse suffix for a single survivor on a statement" do
    single = Saboteur::Report.new(results: [killed, survivors.first], subjects:, wall_time: 62,
                                  root: File.dirname(calculator.file), seed: 1)
    text = render(single, exit_code: 1, quiet: true)
    expect(text).to include("calculator.rb:3 Calculator#compound [missing_test] - #{survivors.first.digest}\n")
    expect(text).not_to include("more)")
  end

  it "prints no label bracket for a survivor the classifier leaves unlabeled" do
    unlabeled = result(:survived, "**years", "**months", covered_by: [])
    report = Saboteur::Report.new(results: [killed, unlabeled], subjects:, wall_time: 62,
                                  root: File.dirname(calculator.file), seed: 1)
    text = render(report, exit_code: 1, quiet: true)
    expect(text).to include("calculator.rb:3 Calculator#compound - #{unlabeled.digest}\n")
  end

  it "takes the label from the group's first survivor in ranked order" do
    labeled = result(:survived, "*", "/", covered_by: ["spec/calculator_spec.rb:7"])
    unlabeled = result(:survived, "+", "-", covered_by: [])
    report = Saboteur::Report.new(results: [killed, labeled, unlabeled], subjects:, wall_time: 62,
                                  root: File.dirname(calculator.file), seed: 1)
    ranked = Saboteur::Reporter::SurvivorRanking.ordered(report, report.unignored_survivors)
    expect(ranked.map { |survivor| Saboteur::Reporter::SurvivorClassification.label(survivor) })
      .to eq(["missing_test", nil])
    text = render(report, exit_code: 1, quiet: true)
    expect(text).to include("[missing_test] - #{ranked.first.digest} (+1 more)\n")
  end

  it "keeps the exit-0 shape: findings and summary, no verdict line" do
    clean = Saboteur::Report.new(results: [killed], subjects: [calculator], wall_time: 62,
                                 root: File.dirname(calculator.file), seed: 1)
    text = render(clean, exit_code: 0, threshold: 80, quiet: true)
    expect(text).to eq("saboteur: 1 killed in 1m02s - score 100.0% (threshold 80)\n")
  end

  # A --baseline gate still owns the closing verdict in quiet: quiet filters
  # the report body, never the gated verdict (#1122's BaselineTail).
  def gate(new_ids:)
    comparison = instance_double(Saboteur::Baseline::Comparison,
                                 categories: { "accepted" => Array.new(411), "new" => new_ids,
                                               "changed" => [], "resolved_kills" => [1],
                                               "detected_timeouts" => [], "unmatched" => [],
                                               "errors" => [] },
                                 score: { "current" => 71.0, "baseline" => 70.8,
                                          "exceeded" => false })
    instance_double(Saboteur::Baseline::RunGate, comparison:, new_survivor_ids: new_ids,
                                                 score_exceeded?: false)
  end

  it "prints the baseline gate verdict instead of the canonical line when gated" do
    text = render(report, exit_code: 1, threshold: 80, quiet: true, baseline_gate: gate(new_ids: %w[a1 b2]))
    expect(text).to include(
      "saboteur: 412 mutants matched the baseline (411 unchanged, 1 fixed) \u00b7 2 new survivors\n",
      "exit 1 - 2 new survivors vs baseline (score 71.0%, was 70.8%)\n"
    )
    expect(text).not_to include("score 25.0%")
  end
end
