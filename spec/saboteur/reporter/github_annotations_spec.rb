# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# Golden GitHub workflow commands (DX wave 3): the finding lands on the
# pull-request diff, so every byte is pinned, including the escaping the
# command parser needs and the line in the current tree.
# Two comment lines push the method body off line 1: the annotation must
# name the line in the current tree, never a stale map position.
ANNOTATIONS_CALCULATOR = <<~RUBY
  # Compound interest over years.
  # Grows the principal by the rate each year.
  class Calculator
    def compound(principal, rate, years)
      principal * (1 + rate)**years
    end
  end
RUBY

ANNOTATIONS_CART = <<~RUBY
  class Cart
    def total = 0
  end
RUBY

RSpec.describe Saboteur::Reporter::GithubAnnotations do
  let(:out) { StringIO.new }
  let(:replay) { ->(digest) { "saboteur run --id #{digest}" } }

  # Both fixtures share one root, the way a project tree does.
  def dir
    @subject_dirs = (@subject_dirs || []) << (@dir ||= File.realpath(Dir.mktmpdir("saboteur-annotations-")))
    @dir
  end

  def subjects_here(source, name)
    path = File.join(dir, name)
    File.write(path, source)
    Saboteur::SubjectFinder.new.call(path).subjects
  end

  def calculator_result(status: :survived, from: "principal * (1 + rate)**years", to: "years",
                        operator: "operand_replacement", **attributes)
    subject = subjects_here(ANNOTATIONS_CALCULATOR, "calculator.rb").first
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

  def render(report)
    out.truncate(0)
    out.rewind
    described_class.new(out, replay_command: replay).call(report)
    out.string
  end

  it "pins one ::error per survivor byte for byte, on the mutant's line in the current tree" do
    survivor = calculator_result
    expect(render(report_for(survivor))).to eq(
      "::error file=calculator.rb,line=5,title=survived mutant (operand_replacement)::" \
      "principal * (1 + rate)**years -> years · spec still passed. " \
      "Replay: saboteur run --id #{survivor.digest}\n"
    )
  end

  it "pins one ::warning per untested subject byte for byte" do
    cart = subjects_here(ANNOTATIONS_CART, "cart.rb").first
    report = report_for(calculator_result(status: :killed),
                        skipped_subjects: { cart => Saboteur::Reporter::ScoreTable::NO_COVERAGE })
    expect(render(report)).to eq(
      "::warning file=cart.rb,line=2,title=subject has no tests::Cart#total is not exercised by any spec\n"
    )
  end

  it "warns for the no tests reason too, the dark-file split C3/C4 adds" do
    cart = subjects_here(ANNOTATIONS_CART, "cart.rb").first
    report = report_for(calculator_result(status: :killed), skipped_subjects: { cart => "no tests" })
    expect(render(report)).to eq(
      "::warning file=cart.rb,line=2,title=subject has no tests::Cart#total is not exercised by any spec\n"
    )
  end

  it "never annotates a survivor accepted on the ignore list" do
    accepted = calculator_result
    accepted.ignored = "boundary covered elsewhere"
    expect(render(report_for(accepted))).to eq("")
  end

  it "annotates nothing when every mutant was killed and every subject is tested" do
    expect(render(report_for(calculator_result(status: :killed)))).to eq("")
  end

  it "percent-encodes %, CR and LF in the message data" do
    survivor = calculator_result(to: "half * 100%\r\n# done")
    expect(render(report_for(survivor))).to include("-> half * 100%25%0D%0A# done ·")
  end

  it "escapes a comma or colon in a property value, since they terminate a property (#1165)" do
    subject = subjects_here(ANNOTATIONS_CART, "weird,name.rb").first
    report = report_for(calculator_result(status: :killed),
                        skipped_subjects: { subject => Saboteur::Reporter::ScoreTable::NO_COVERAGE })
    expect(render(report)).to start_with("::warning file=weird%2Cname.rb,line=2,title=subject has no tests::Cart#total")
  end

  it "leaves the comma and colon of the message data alone" do
    survivor = calculator_result(to: "half: 1, done")
    expect(render(report_for(survivor))).to include("-> half: 1, done ·")
  end
end
