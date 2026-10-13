# SPDX-License-Identifier: MIT
# frozen_string_literal: true

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
        "or_assign" => "try an example where the variable is already set (||= vs =)",
        "safe_navigation" => "try an example where the receiver is nil",
        "argument_removal" => "try have_received(...).with(...), or assert a result that depends on this argument",
        "pair_removal" => "try have_received(...).with(...), or assert the hash content under this key",
        "endpoint_replacement" => "try a collection with 2 or more elements, to tell first from last",
        "filter_replacement" => "try items that match and items that do not, to tell select from reject"
      }.freeze

      COARSE = "try asserting this method's result or its effect"

      # Printed once after the survivors: a hint is a place to look, not a diagnosis.
      CAVEAT = "Hints are suggestions, not diagnoses: a survivor can also be an equivalent mutant, or a change " \
               "the selected tests cannot observe."

      module_function

      def for(operator, coarse: false)
        BY_OPERATOR.fetch(operator) { coarse ? COARSE : nil }
      end
    end
  end
end
