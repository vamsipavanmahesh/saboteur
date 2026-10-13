# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Says what kind of test would kill a surviving mutant, by operator. The
    # hint is a lead, not proof: the survivor can also be an equivalent mutant.
    module SurvivorHints
      BY_OPERATOR = {
        "comparison" => "no example sits on the boundary: add one where the compared values are equal " \
                        "or differ by one",
        "arithmetic" => "no example checks the computed number: assert the exact result",
        "boolean_logic" => "no example makes each side of the condition decide the outcome alone",
        "negation_removal" => "no example where the negated value flips the result",
        "literal_number" => "no example uses this number: assert something that depends on its value",
        "literal_boolean" => "no example depends on this true/false value",
        "literal_string" => "no assertion on this text",
        "statement_removal" => "no example notices this statement is gone: assert its effect",
        "or_assign" => "no example where the variable is already set (||= vs =)",
        "safe_navigation" => "no example where the receiver is nil",
        "argument_removal" => "no example checks this argument: use have_received(...).with(...) " \
                              "or assert the result that depends on it",
        "pair_removal" => "no example checks this key: assert the hash content that depends on it",
        "endpoint_replacement" => "no example tells first from last: use a collection with 2 or more elements",
        "filter_replacement" => "no example tells select from reject: include both matching and " \
                                "non-matching items"
      }.freeze

      COARSE = "no example checks what this method returns or does: assert its result or its effect"

      module_function

      def for(operator, coarse: false)
        BY_OPERATOR.fetch(operator) { coarse ? COARSE : nil }
      end
    end
  end
end
