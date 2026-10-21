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
    expect(text).to include("1. person.rb:2 Person#adult?")
  end

  it "gives a whole-method mutant its whole-method suggestion" do
    expect(render(report_of(result_for(:survived, coarse: true)))).to include(
      "\u2192 try asserting this method's result or its effect"
    )
  end

  it "prints no hint line, and no caveat, for an operator without a suggestion" do
    mutation = Saboteur::MutationSource::Mutation.new(
      subject_id: person_subject.id, operator: "made_up", edits: comparison_mutation.edits, coarse: false
    )
    result = Saboteur::MutantResult.new(subject: person_subject, mutation:, status: :survived,
                                        mutated_source: person_subject.apply(mutation.edits))
    text = render(report_of(result))
    expect(text).to include("made_up \u00b7")
    expect(text).not_to include("\u2192", "Hints are suggestions")
  end
end

RSpec.describe Saboteur::Reporter::SurvivorHints, "label gating and block prose" do
  it "hints every label except likely_equivalent" do
    expect(described_class.for_label("arithmetic",
                                     label: "missing_test")).to eq("try asserting the exact computed number")
    expect(described_class.for_label("arithmetic", label: nil)).to eq("try asserting the exact computed number")
    expect(described_class.for_label("arithmetic", label: "likely_equivalent")).to be_nil
  end

  it "passes coarse through to the operator hint" do
    expect(described_class.for_label("unknown_op", label: "missing_test", coarse: true))
      .to eq(described_class.for("unknown_op", coarse: true))
  end

  it "answers the per-operator why-it-matters sentence, with a fallback" do
    expect(described_class.why("operand_replacement")).to eq("the result no longer depends on the replaced operand")
    expect(described_class.why("made_up")).to eq("no test observes this change")
  end

  it "answers the per-label reason, nil for an unlabeled or unknown label" do
    expect(described_class.label_reason("likely_equivalent")).to eq("compiles to the same instructions as the original")
    expect(described_class.label_reason("made_up")).to be_nil
    expect(described_class.label_reason(nil)).to be_nil
  end
end
