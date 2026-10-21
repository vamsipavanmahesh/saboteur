# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

# Golden GitHub step summary (PR12): the markdown lands in the Actions run
# page, so the table and the survivor list are pinned byte for byte.
STEP_SUMMARY_CALCULATOR = <<~RUBY
  # Compound interest over years.
  # Grows the principal by the rate each year.
  class Calculator
    def compound(principal, rate, years)
      principal * (1 + rate)**years
    end
  end
RUBY

STEP_SUMMARY_CART = <<~RUBY
  class Cart
    def total = 0
  end
RUBY

RSpec.describe Saboteur::Reporter::StepSummary do
  def dir
    @subject_dirs = (@subject_dirs || []) << (@dir ||= File.realpath(Dir.mktmpdir("saboteur-summary-")))
    @dir
  end

  def subjects_here(source, name)
    path = File.join(dir, name)
    File.write(path, source)
    Saboteur::SubjectFinder.new.call(path).subjects
  end

  def calculator_result(status: :survived, from: "principal * (1 + rate)**years", to: "years",
                        operator: "operand_replacement", **attributes)
    subject = subjects_here(STEP_SUMMARY_CALCULATOR, "calculator.rb").first
    at = subject.file_source.index(from, subject.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + from.size,
                                              replacement: to)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator:, edits: [edit],
                                                      coarse: false)
    Saboteur::MutantResult.new(subject:, mutation:, status:,
                               mutated_source: subject.apply(mutation.edits), **attributes)
  end

  def report_for(*results, skipped_subjects: {})
    root = File.dirname((results.first || skipped_subjects.keys.first).subject.file)
    Saboteur::Report.new(results:, subjects: results.map(&:subject).uniq | skipped_subjects.keys,
                         wall_time: 1.0, root:, warnings: [], seed: 1, skipped_subjects:)
  end

  def summary_for(report)
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, "summary.md")
      described_class.new(env: { "GITHUB_STEP_SUMMARY" => path }).call(report)
      File.read(path)
    end
  end

  it "writes nothing when the variable is unset" do
    expect(described_class.new(env: {}).call(report_for(calculator_result(status: :killed)))).to be_nil
  end

  it "pins the whole summary: score pair per file, untested subjects named, survivors with digests" do
    survivor = calculator_result
    cart = subjects_here(STEP_SUMMARY_CART, "cart.rb").first
    report = report_for(calculator_result(status: :killed), survivor,
                        skipped_subjects: { cart => Saboteur::Reporter::ScoreTable::NO_COVERAGE })
    expect(summary_for(report)).to eq(<<~MD)
      ## Saboteur mutation report

      | File | Score (tested subjects) | Untested subjects |
      | --- | --- | --- |
      | calculator.rb | 50.0% (1/2) | 0 |
      | cart.rb | n/a | 1: Cart#total |

      ### Surviving mutants

      - `#{survivor.digest}` calculator.rb:5 (operand_replacement): `principal * (1 + rate)**years` -> `years`
    MD
  end

  it "keeps accepted survivors out of the survivor list" do
    accepted = calculator_result
    accepted.ignored = "boundary covered elsewhere"
    expect(summary_for(report_for(accepted))).not_to include("### Surviving mutants")
  end

  it "appends to a summary a prior step wrote instead of truncating it" do
    Dir.mktmpdir do |tmp|
      path = File.join(tmp, "summary.md")
      File.write(path, "## Earlier step\n")
      described_class.new(env: { "GITHUB_STEP_SUMMARY" => path }).call(report_for(calculator_result(status: :killed)))
      expect(File.read(path)).to start_with("## Earlier step\n## Saboteur mutation report\n")
    end
  end

  it "fences a substitution holding a backtick with a double backtick" do
    survivor = calculator_result(to: "`tick`")
    expect(summary_for(report_for(survivor))).to include("-> `` `tick` ``\n")
  end
end
