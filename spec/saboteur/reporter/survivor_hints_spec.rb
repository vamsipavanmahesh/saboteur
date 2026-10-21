# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Reporter::SurvivorHints do
  it "gives the operator's own suggestion, coarse or not" do
    expect(described_class.for("comparison")).to start_with("try an example at the boundary")
    expect(described_class.for("comparison", coarse: true)).to start_with("try an example at the boundary")
  end

  it "falls back to the whole-method suggestion only for a coarse mutant of an unlisted operator" do
    expect(described_class.for("body_nil", coarse: true)).to eq("try asserting this method's result or its effect")
    expect(described_class.for("made_up")).to be_nil
    expect(described_class.for("made_up", coarse: false)).to be_nil
  end

  it "appends a conditional equivalence confirmation to the chain_removal hint (#264)" do
    expect(described_class.for("chain_removal")).to eq(
      "try the shorter chain's value against the longer one; if you confirm the shorter chain is " \
      "equivalent across the intended inputs (for example a duplicated column), simplify the code or " \
      "ignore the mutant"
    )
  end
end

RSpec.describe Saboteur::Reporter::SurvivorHints, ".structured" do
  def hint(operator, original = "x", replacement = "y", coarse: false)
    described_class.structured(operator: operator, original: original, replacement: replacement, coarse: coarse)
  end

  it "names the equal-operands case when the swap differs only there" do
    [%w[> >=], %w[>= >], %w[< <=], %w[<= <]].each do |original, replacement|
      expect(hint("comparison", original, replacement)).to include(kind: "boundary", case: "left == right")
    end
  end

  it "names the unequal-operands case for a flip" do
    [%w[< >], %w[> <], %w[<= >=], %w[>= <=]].each do |original, replacement|
      expect(hint("comparison", original, replacement)).to include(kind: "boundary", case: "left != right")
    end
  end

  it "gives a plain assertion hint when no case is known" do
    expect(hint("comparison", "<", "==")).to eq(kind: "assertion", text: described_class.for("comparison"))
    expect(hint("arithmetic")).to eq(kind: "assertion", text: described_class.for("arithmetic"))
  end

  it "names a coarse mutant of an unlisted operator as a method result check" do
    expect(hint("body_nil", coarse: true)).to eq(kind: "method_result", text: described_class::COARSE)
  end

  it "is nil without a hint, and ignores operator text on a non-comparison operator" do
    expect(hint("made_up")).to be_nil
    expect(hint("arithmetic", ">", ">=")).not_to include(:case)
  end
end

RSpec.describe Saboteur::Reporter::SurvivorList do
  def render(report)
    out = StringIO.new
    Saboteur::Reporter::Terminal.new(out, all_mutants: true).call(report)
    out.string
  end

  it "prints the file, then the method, then the line" do
    text = render(report_of(result_for(:survived)))
    expect(text).to include("\nperson.rb\n  Person#adult?\n    person.rb:2 in Person#adult?\n")
  end

  it "gives a whole-method mutant its whole-method suggestion" do
    expect(render(report_of(result_for(:survived, coarse: true)))).to include(
      "hint: try asserting this method's result or its effect"
    )
  end

  it "prints no hint line, and no caveat, for an operator without a suggestion" do
    mutation = Saboteur::MutationSource::Mutation.new(
      subject_id: person_subject.id, operator: "made_up", edits: comparison_mutation.edits, coarse: false
    )
    result = Saboteur::MutantResult.new(subject: person_subject, mutation:, status: :survived,
                                        mutated_source: person_subject.apply(mutation.edits))
    text = render(report_of(result))
    expect(text).to include("- made_up >= ->")
    expect(text).not_to include("hint:", "Hints are suggestions")
  end
end
