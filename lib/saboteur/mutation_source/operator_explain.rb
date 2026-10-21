# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "operator_examples"
require_relative "operator_registry"

module Saboteur
  module MutationSource
    # Curated text behind `saboteur explain NAME`. The definition and the
    # example stay shared with --list-operators (one wording source); the
    # survival and kill hints below are the only text owned here. Every
    # registry operator needs an entry: the coverage spec fails the build
    # when one ships without it.
    module OperatorExplain
      Entry = Data.define(:name, :definition, :example, :survives, :kill)

      GUIDANCE = {
        "body_nil" => {
          survives: "the method is called for side effects and no test asserts the return value.",
          kill: "an assertion on the exact return value, or on a caller behaviour that depends on it."
        },
        "body_true" => {
          survives: "tests never check the predicate outcome, or only take the path true already forces.",
          kill: "an example whose input makes the predicate false, asserting that path is taken."
        },
        "body_false" => {
          survives: "tests never check the predicate outcome, or only take the path false already forces.",
          kill: "an example whose input makes the predicate true, asserting that path is taken."
        },
        "body_raise" => {
          survives: "tests stub or skip the method, or wrap the call in a broad rescue.",
          kill: "any test that calls the method and lets it complete; the raise fails that example."
        },
        "comparison" => {
          survives: "tests never use values at the boundary the change moves, such as equal values for < vs <=.",
          kill: "a boundary example: the equal case, or the two values just either side of the operator."
        },
        "arithmetic" => {
          survives: "tests assert the result loosely (type, presence, sign) instead of its exact value.",
          kill: "an assertion on the exact computed value with operands where the two operators differ."
        },
        "boolean_logic" => {
          survives: "tests never exercise the dropped operand deciding the outcome on its own.",
          kill: "one example per operand where that operand alone flips the result, asserting each outcome."
        },
        "condition_true" => {
          survives: "tests only exercise the branch the forced condition takes.",
          kill: "an example with a falsy input, asserting the else branch still runs."
        },
        "condition_false" => {
          survives: "tests only exercise the branch the forced condition takes.",
          kill: "an example with a truthy input, asserting the then branch still runs."
        },
        "negation_removal" => {
          survives: "tests assert loosely, or never cover the input the negation inverts.",
          kill: "assert the behaviour for both a truthy and a falsy input through the public API."
        },
        "literal_number" => {
          survives: "the literal flows into nothing a test asserts, or every fixture value works for both.",
          kill: "an assertion on the exact value the literal feeds (a total, a limit, an index)."
        },
        "or_assign" => {
          survives: "tests only cover the nil or false case, where both forms assign.",
          kill: "an example where the variable is already truthy and must keep its value."
        },
        "and_assign" => {
          survives: "tests only cover the truthy case, where both forms assign.",
          kill: "an example where the variable is falsy and must stay untouched."
        },
        "safe_navigation" => {
          survives: "the receiver is never nil in any covering test.",
          kill: "an example with a nil receiver asserting nil comes back instead of NoMethodError."
        },
        "statement_removal" => {
          survives: "the removed statement's effect is never observed: an unasserted side effect or return.",
          kill: "assert the side effect (a spy, a state change) or the value the statement produced."
        },
        "copy_replacement" => {
          survives: "tests never mutate the returned object, so the aliasing goes unnoticed.",
          kill: "mutate what the method returns and assert the original is unchanged (or assert a copy)."
        },
        "filter_replacement" => {
          survives: "tests assert loosely, or the fixture collection is empty or all one kind.",
          kill: "assert the exact surviving elements of a mixed collection, in order."
        },
        "literal_string" => {
          survives: "no test asserts the string's content, only that something was returned.",
          kill: "an exact string equality assertion on the value that carries the literal."
        },
        "literal_boolean" => {
          survives: "the boolean is never asserted, or both values pass the covering assertions.",
          kill: "an example whose expected behaviour flips with the boolean."
        },
        "argument_swap" => {
          survives: "tests use equal or interchangeable arguments, or assert the result loosely.",
          kill: "asymmetric arguments with an assertion on the exact result order."
        },
        "argument_removal" => {
          survives: "the removed argument changes nothing the covering tests observe.",
          kill: "a case where that argument changes the result, asserted exactly."
        },
        "pair_removal" => {
          survives: "tests never read the removed key, directly or through a consumer.",
          kill: "assert the value stored under the removed key, or the whole hash."
        },
        "element_removal" => {
          survives: "tests never exercise the removed element of the array.",
          kill: "an example per element whose behaviour changes when that element is missing."
        },
        "endpoint_replacement" => {
          survives: "fixture collections have one element, or the wrong end is never asserted.",
          kill: "a multi-element collection with an assertion on exactly which end comes back."
        },
        "chain_removal" => {
          survives: "in every tested case the skipped call returns an equivalent value.",
          kill: "a case where the removed call changes the value, asserted exactly."
        },
        "range" => {
          survives: "tests never use the endpoint the exclusive range drops.",
          kill: "an example whose input is the boundary value, asserting it is included."
        },
        "operator_assignment" => {
          survives: "tests check the variable changed, not its exact new value.",
          kill: "assert the exact value after the assignment, where += and -= disagree."
        },
        "condition_negation" => {
          survives: "tests only cover the side of the predicate the negation keeps.",
          kill: "assert both branches with inputs on each side of the predicate."
        },
        "method_swap" => {
          survives: "tests assert loosely, or min and max coincide in every fixture.",
          kill: "a fixture where the two methods differ, asserting the exact expected one."
        },
        "operand_replacement" => {
          survives: "tests assert the result loosely (present, positive, non-nil) or never exercise " \
                    "the removed operand.",
          kill: "an assertion on the exact value through the public API, with inputs where the " \
                "removed operand changes the result."
        },
        "interpolation_removal" => {
          survives: "no test asserts the full interpolated content of the string.",
          kill: "an exact string assertion with a known value in the interpolation."
        },
        "jump_value" => {
          survives: "callers ignore the returned value, or tests never take that return path.",
          kill: "an example that takes the early return and asserts the exact value it hands back."
        },
        "rescue_removal" => {
          survives: "tests never raise the error the handler rescues.",
          kill: "an example raising that error, asserting the handler's fallback behaviour."
        },
        "ensure_removal" => {
          survives: "the cleanup's effect is never observed on the tested paths.",
          kill: "assert the cleanup ran (resource released, flag reset), including on the error path."
        },
        "when_removal" => {
          survives: "tests never hit the removed branch of the case.",
          kill: "one example per when branch, asserting its exact outcome."
        },
        "unary_removal" => {
          survives: "fixtures use zero or symmetric values, or tests assert loosely.",
          kill: "an assertion on the exact signed or complemented value with a non-trivial input."
        },
        "regex_replacement" => {
          survives: "every test input matches under both the original and the loosened regex.",
          kill: "an input the anchor or quantifier excludes, asserting it is rejected."
        }
      }.freeze

      # nil for an unknown name; the command turns that into the exit-2 error.
      def self.for(name)
        return unless OperatorRegistry::DESCRIPTIONS.key?(name)

        guidance = GUIDANCE.fetch(name)
        Entry.new(name:, definition: OperatorRegistry::DESCRIPTIONS.fetch(name),
                  example: OperatorExamples::EXAMPLES.fetch(name),
                  survives: guidance.fetch(:survives), kill: guidance.fetch(:kill))
      end
    end
  end
end
