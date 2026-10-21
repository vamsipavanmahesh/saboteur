# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

# saboteur explain <operator> (#1097): definition, example and kill
# guidance for one operator, from the curated registry content.
RSpec.describe Saboteur::CLI, "explain (#1097)" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    described_class.new(argv, out:, err:)
  end

  it "prints the pinned operand_replacement card, monochrome on a pipe" do
    expect(cli("explain", "operand_replacement").call).to eq(0)
    expect(out.string).to eq(<<~TEXT)
      Operator: operand_replacement
      Definition: Replace a binary operation with one operand
      Example:
        - a + b
        + a
      Survives when: tests assert the result loosely (present, positive, non-nil) or never exercise the removed operand.
      Kill it with: an assertion on the exact value through the public API, with inputs where the removed operand changes the result.
    TEXT
  end

  it "prints the pinned condition_negation card" do
    expect(cli("explain", "condition_negation").call).to eq(0)
    expect(out.string).to eq(<<~TEXT)
      Operator: condition_negation
      Definition: Negate if, unless and ternary predicates
      Example:
        - x ? a : b
        + !(x) ? a : b
      Survives when: tests only cover the side of the predicate the negation keeps.
      Kill it with: assert both branches with inputs on each side of the predicate.
    TEXT
  end

  it "prints the pinned body_nil card" do
    expect(cli("explain", "body_nil").call).to eq(0)
    expect(out.string).to eq(<<~TEXT)
      Operator: body_nil
      Definition: Replace the method body with nil
      Example:
        - def value = 1
        + def value = nil
      Survives when: the method is called for side effects and no test asserts the return value.
      Kill it with: an assertion on the exact return value, or on a caller behaviour that depends on it.
    TEXT
  end

  it "paints the pinned colour card when colour is on" do
    entry = Saboteur::MutationSource::OperatorExplain.for("operand_replacement")
    palette = Saboteur::Reporter::Palette.new(enabled: true)
    rendered = cli("explain").send(:render_explain, entry, palette:)
    expect(rendered).to eq(
      "\e[1mOperator:\e[0m operand_replacement\n" \
      "\e[1mDefinition:\e[0m Replace a binary operation with one operand\n" \
      "\e[1mExample:\e[0m\n  " \
      "\e[31;1m- a + b\e[0m\n  " \
      "\e[32m+ a\e[0m\n" \
      "\e[33mSurvives when:\e[0m tests assert the result loosely (present, positive, non-nil) or never " \
      "exercise the removed operand.\n" \
      "\e[36mKill it with:\e[0m an assertion on the exact value through the public API, with inputs where " \
      "the removed operand changes the result."
    )
  end

  it "exits 2 for an unknown operator, naming it and listing the valid names" do
    expect(cli("explain", "not_an_operator").call).to eq(2)
    expect(err.string).to include("saboteur: unknown operator: not_an_operator")
    expect(err.string).to include("operand_replacement", "condition_negation", "body_nil")
    expect(out.string).to eq("")
  end

  it "suggests the closest operator for a typo" do
    expect(cli("explain", "operand_replacment").call).to eq(2)
    expect(err.string).to include("saboteur: Did you mean operand_replacement?")
  end

  it "exits 2 with usage when no operator is named" do
    expect(cli("explain").call).to eq(2)
    expect(err.string).to include("saboteur: usage: saboteur explain <operator>")
  end
end
