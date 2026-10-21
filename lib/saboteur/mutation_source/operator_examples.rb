# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module MutationSource
    module OperatorExamples
      EXAMPLES = {
        "body_nil" => "def value = 1 -> def value = nil",
        "body_true" => "def ok? = false -> def ok? = true",
        "body_false" => "def ok? = true -> def ok? = false",
        "body_raise" => "def value = 1 -> def value; raise; end",
        "comparison" => "a < b -> a <= b",
        "arithmetic" => "a + b -> a - b",
        "boolean_logic" => "a && b -> a",
        "condition_true" => "if x -> if true",
        "condition_false" => "if x -> if false",
        "negation_removal" => "!x -> x",
        "literal_number" => "1 -> 0",
        "or_assign" => "x ||= 1 -> x = 1",
        "and_assign" => "x &&= y -> x = y",
        "safe_navigation" => "x&.name -> x.name",
        "statement_removal" => "check; value -> nil; value",
        "copy_replacement" => "x.dup -> x",
        "filter_replacement" => "xs.select { |x| x } -> xs.reject { |x| x }",
        "literal_string" => "\"hello\" -> \"\"",
        "literal_boolean" => "true -> false",
        "argument_swap" => "send(a, b) -> send(b, a)",
        "argument_removal" => "send(a, b) -> send(a)",
        "pair_removal" => "{a: 1, b: 2} -> {b: 2}",
        "element_removal" => "TAGS = [a, b] -> TAGS = [b]",
        "endpoint_replacement" => "xs.first -> xs.last",
        "chain_removal" => "x.first.to_s -> x.to_s",
        "range" => "1..3 -> 1...3",
        "operator_assignment" => "x += 1 -> x -= 1",
        "condition_negation" => "x ? a : b -> !(x) ? a : b",
        "method_swap" => "xs.min -> xs.max",
        "operand_replacement" => "a + b -> a",
        "interpolation_removal" => "\"hi \#{name}\" -> \"hi \"",
        "jump_value" => "return total -> return nil",
        "rescue_removal" => "begin; x; rescue; y; end -> begin; x; end",
        "ensure_removal" => "begin; x; ensure; y; end -> begin; x; end",
        "when_removal" => "case x; when 1 then a; when 2 then b; end -> case x; when 2 then b; end",
        "unary_removal" => "-x -> x",
        "unary_insertion" => "a && b -> a && !b",
        "break_next_swap" => "break x -> next x",
        "regex_replacement" => "/\\A\\d+\\z/ -> /\\d+\\z/"
      }.freeze
    end
  end
end
