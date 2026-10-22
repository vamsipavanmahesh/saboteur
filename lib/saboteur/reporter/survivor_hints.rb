# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "gap_kinds"

module Saboteur
  module Reporter
    # Suggests a check that might kill a surviving mutant, by operator. It does
    # not say what is missing: the survivor can also be an equivalent mutant.
    module SurvivorHints
      BY_OPERATOR = {
        "comparison" => "try an example at the boundary: equal values, or values one apart",
        "arithmetic" => "try asserting the exact computed number",
        "boolean_logic" => "try an example where each side of the condition alone decides the result",
        "negation_removal" => "try an example where the negated value changes the result",
        "literal_number" => "try asserting something that depends on this number",
        "literal_boolean" => "try an example that depends on this true/false value",
        "literal_string" => "try asserting on this text",
        "statement_removal" => "try asserting the effect of this statement",
        "and_assign" => "try an example where the variable is nil or false (&&= vs =)",
        "or_assign" => "try an example where the variable is already set (||= vs =)",
        "safe_navigation" => "try an example where the receiver is nil",
        "argument_removal" => "try have_received(...).with(...), or assert a result that depends on this argument",
        "pair_removal" => "try have_received(...).with(...), or assert the hash content under this key",
        "chain_removal" => "try the shorter chain's value against the longer one; if you confirm the " \
                           "shorter chain is equivalent across the intended inputs (for example a duplicated " \
                           "column), simplify the code or ignore the mutant",
        "endpoint_replacement" => "try a collection with 2 or more elements, to tell first from last",
        "jump_value" => "try asserting the value this early exit returns",
        "rescue_removal" => "try an example where the guarded code raises, and assert what the handler returns",
        "ensure_removal" => "try asserting the cleanup effect of the ensure clause",
        "when_removal" => "try a value that only this when branch matches, and assert its result",
        "unary_removal" => "try a value where the sign or complement changes the result",
        "copy_replacement" => "try changing the result after the call and check the original is untouched",
        "filter_replacement" => "try items that match and items that do not, to tell select from reject"
      }.freeze

      COARSE = "try asserting this method's result or its effect"

      # Printed once after the survivors: a hint is a place to look, not a diagnosis.
      CAVEAT = "Hints are suggestions, not diagnoses: a survivor can also be an equivalent mutant, or a change " \
               "the selected tests cannot observe."

      # Comparison operator swaps where the two operators give the same answer
      # except in one named case, so a test that hits that case can tell them
      # apart. Anything else gets the plain text hint.
      EQUAL_CASE = [%w[< <=], %w[> >=]].map(&:to_set).freeze
      UNEQUAL_CASE = [%w[< >], %w[<= >=]].map(&:to_set).freeze

      # Labels that never get a hint: a generated assertion on an equivalent
      # mutant is the worst kind of hint noise. The assertion_gap/input_gap
      # split (#1064) narrows this further; until it lands, every other
      # label keeps the operator hint unchanged.
      NO_HINT_LABELS = %w[likely_equivalent].freeze

      # One deterministic template sentence per operator: what the change
      # means for behaviour, never an inference beyond the operator.
      WHY_IT_MATTERS = {
        "comparison" => "the boundary between the two comparisons is untested",
        "arithmetic" => "the computed value can drift without a test noticing",
        "boolean_logic" => "one side of the condition no longer decides the result",
        "condition_negation" => "the condition now picks the opposite branch",
        "negation_removal" => "the negated value is no longer distinguished",
        "literal_number" => "no test depends on this exact number",
        "literal_boolean" => "no test depends on this exact true/false value",
        "literal_string" => "no test asserts on this exact text",
        "statement_removal" => "the statement's effect goes unobserved",
        "and_assign" => "the nil-or-false case of &&= is untested",
        "or_assign" => "the already-set case of ||= is untested",
        "safe_navigation" => "a nil receiver now behaves like any other value",
        "argument_removal" => "the call no longer depends on this argument",
        "argument_swap" => "the argument order no longer matters to any test",
        "pair_removal" => "the hash no longer depends on this key",
        "chain_removal" => "part of the call chain has no observable effect",
        "endpoint_replacement" => "first and last are no longer distinguished",
        "jump_value" => "the early exit's value goes unobserved",
        "rescue_removal" => "the rescue handler's behaviour goes unobserved",
        "ensure_removal" => "the ensure cleanup's effect goes unobserved",
        "when_removal" => "the values only this branch matches are untested",
        "unary_removal" => "the sign or complement change goes unobserved",
        "copy_replacement" => "aliasing and copying are no longer distinguished",
        "filter_replacement" => "select and reject are no longer distinguished",
        "interpolation_removal" => "the interpolated value goes unobserved",
        "regex_replacement" => "the pattern's matched set changed unnoticed",
        "method_swap" => "the swapped method's different behaviour goes unobserved",
        "element_removal" => "the removed element goes unobserved",
        "operand_replacement" => "the result no longer depends on the replaced operand",
        "operator_assignment" => "the combined assignment operation goes unobserved"
      }.freeze
      WHY_FALLBACK = "no test observes this change"

      # The deterministic per-label reason printed next to a survivor's rank.
      # Labels come from SurvivorClassification; they are heuristics, not
      # diagnoses. #1064 lands the assertion_gap label: add its reason here
      # and its gate in NO_HINT_LABELS when it does.
      LABEL_REASONS = {
        "likely_equivalent" => "compiles to the same instructions as the original",
        "arid" => "every edited line matches an arid pattern",
        "tool_limit" => "the tool could not observe this mutant faithfully",
        "input_gap" => "no test reached this mutant, so its input never varied"
      }.merge(GapKinds::REASONS).freeze

      module_function

      # The hint for a labeled survivor; nil when the label suppresses hints.
      def for_label(operator, label:, coarse: false)
        return nil if NO_HINT_LABELS.include?(label)

        self.for(operator, coarse: coarse)
      end

      # The per-operator "why it matters" sentence for a survivor block.
      def why(operator)
        WHY_IT_MATTERS.fetch(operator, WHY_FALLBACK)
      end

      # The per-label reason sentence; nil when the label has none.
      def label_reason(label)
        LABEL_REASONS[label]
      end

      def for(operator, coarse: false)
        BY_OPERATOR.fetch(operator) { coarse ? COARSE : nil }
      end

      # The hint as data for `--agent`: { kind:, text: } and, for a comparison
      # swap, case: the relation between the two operands that separates the
      # original from the mutant ("left == right"). It is where to look, not a
      # promise that a test there will kill the mutant. nil when there is none.
      def structured(operator:, original:, replacement:, coarse: false)
        text = self.for(operator, coarse: coarse)
        return unless text

        operands = boundary_case(operator, original, replacement)
        return { kind: "boundary", case: operands, text: text } if operands

        { kind: coarse ? "method_result" : "assertion", text: text }
      end

      def boundary_case(operator, original, replacement)
        return unless operator == "comparison"

        pair = Set[original, replacement]
        return "left == right" if EQUAL_CASE.include?(pair)

        "left != right" if UNEQUAL_CASE.include?(pair)
      end
    end
  end
end
