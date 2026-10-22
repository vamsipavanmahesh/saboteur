# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # The gap-kind vocabulary (D2): which sort of check a survivor suggests
    # is missing, as a LABEL ONLY (#192) - a heuristic from the operator and
    # the edit shape, never a diagnosis, and never a score input.
    module GapKinds
      KINDS = %w[boundary branch effect number] + ["error path", "result unchecked"].freeze

      # Operator -> gap kind, every built-in operator exactly once except
      # operand_replacement, whose kind depends on the replaced expression
      # (a comparison loses its boundary; anything else is a plain result).
      # Anything missing here - a new operator before its row lands - is
      # the honest fallback: result unchecked.
      BY_OPERATOR = {
        "comparison" => "boundary",
        "range" => "boundary",
        "endpoint_replacement" => "boundary",
        "condition_negation" => "branch",
        "condition_true" => "branch",
        "condition_false" => "branch",
        "boolean_logic" => "branch",
        "negation_removal" => "branch",
        "when_removal" => "branch",
        "safe_navigation" => "branch",
        "filter_replacement" => "branch",
        "statement_removal" => "effect",
        "element_removal" => "effect",
        "argument_removal" => "effect",
        "pair_removal" => "effect",
        "chain_removal" => "effect",
        "copy_replacement" => "effect",
        "literal_number" => "number",
        "arithmetic" => "number",
        "unary_removal" => "number",
        "operator_assignment" => "number",
        "rescue_removal" => "error path",
        "ensure_removal" => "error path",
        "body_raise" => "error path",
        "body_nil" => "result unchecked",
        "body_true" => "result unchecked",
        "body_false" => "result unchecked",
        "literal_string" => "result unchecked",
        "literal_boolean" => "result unchecked",
        "or_assign" => "result unchecked",
        "and_assign" => "result unchecked",
        "argument_swap" => "result unchecked",
        "method_swap" => "result unchecked",
        "interpolation_removal" => "result unchecked",
        "jump_value" => "result unchecked",
        "regex_replacement" => "result unchecked"
      }.freeze

      # The one operator whose kind comes from the edit shape, not the name.
      SHAPE_DECIDED = %w[operand_replacement].freeze

      FALLBACK = "result unchecked"

      # Which kind names a statement when its surviving mutants disagree
      # (#P4): the first one listed that any of them carries. The broadest
      # unchecked thing wins, so a branch condition is not called a
      # boundary because one of its mutants happened to flip a comparison.
      PRECEDENCE = ["result unchecked", "error path", "branch", "boundary", "effect", "number"].freeze

      # The deterministic per-kind reason printed next to a survivor's rank.
      REASONS = {
        "boundary" => "the covering specs pass without pinning this boundary",
        "branch" => "the covering specs pass without pinning this branch",
        "effect" => "the covering specs pass without pinning this effect",
        "number" => "the covering specs pass without pinning this number",
        "error path" => "the covering specs pass without pinning this error path",
        "result unchecked" => "the covering specs pass without pinning this result"
      }.freeze

      module_function

      def kind(operator, comparison_edit: false)
        return comparison_edit ? "boundary" : FALLBACK if SHAPE_DECIDED.include?(operator)

        BY_OPERATOR.fetch(operator, FALLBACK)
      end
    end
  end
end
