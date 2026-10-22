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

  # Exact bytes: the ", " separator, the prefixed list line and the absent
  # empty-suggestion line are all pinned, so a joined-without-separator,
  # interpolation-free or always-printed suggestion mutant cannot pass.
  it "exits 2 for an unknown operator, with the exact stderr card" do
    expect(cli("explain", "not_an_operator").call).to eq(2)
    expect(err.string).to eq(
      "saboteur: unknown operator: not_an_operator\n" \
      "saboteur: operators: #{Saboteur::MutationSource::OperatorRegistry::DESCRIPTIONS.keys.join(', ')}\n"
    )
    expect(out.string).to eq("")
  end

  # The palette keyword is behaviour, not decoration: on a tty the card is
  # painted through the auto palette, so dropping it (and falling back to
  # the monochrome default) cannot pass. The colour env keys are scrubbed
  # so the answer does not depend on the ambient terminal.
  it "colours the card when the output stream is a tty" do
    tty = StringIO.new.tap { |io| allow(io).to receive(:tty?).and_return(true) }
    with_colour_env do
      expect(described_class.new(%w[explain operand_replacement], out: tty, err:).call).to eq(0)
      expect(tty.string).to include("\e[1mOperator:\e[0m")
    end
  end

  def with_colour_env
    keys = %w[NO_COLOR FORCE_COLOR CLICOLOR_FORCE TERM]
    saved = keys.to_h { |k| [k, ENV.delete(k)] }
    yield
  ensure
    keys.each { |k| saved[k] ? ENV[k] = saved[k] : ENV.delete(k) }
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
