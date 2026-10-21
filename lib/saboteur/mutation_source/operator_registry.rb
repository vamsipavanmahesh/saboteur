# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "did_you_mean"
require_relative "operator_examples"

module Saboteur
  module MutationSource
    # Public names used by selection, help and inline suppression validation.
    module OperatorRegistry
      DESCRIPTIONS = {
        "operator_assignment" => "Swap arithmetic compound assignments",
        "condition_negation" => "Negate if, unless and ternary predicates",
        "range" => "Swap inclusive and exclusive bounded ranges",
        "body_nil" => "Replace the method body with nil",
        "body_true" => "Replace a predicate body with true",
        "body_false" => "Replace a predicate body with false",
        "body_raise" => "Replace the method body with raise",
        "comparison" => "Change a comparison or replace its result",
        "arithmetic" => "Swap an arithmetic operator",
        "boolean_logic" => "Change a boolean connector",
        "condition_true" => "Force a condition true",
        "condition_false" => "Force a condition false",
        "negation_removal" => "Remove a logical negation",
        "literal_number" => "Change a numeric literal",
        "or_assign" => "Replace ||= with assignment",
        "and_assign" => "Replace &&= with assignment",
        "safe_navigation" => "Replace safe navigation with a regular call",
        "statement_removal" => "Replace a statement with nil",
        "filter_replacement" => "Swap select and reject",
        "copy_replacement" => "Drop a dup or clone, or make deep_dup shallow",
        "literal_string" => "Empty a string literal",
        "literal_boolean" => "Swap a boolean literal",
        "argument_swap" => "Swap two positional call arguments",
        "argument_removal" => "Remove a call argument",
        "pair_removal" => "Remove a hash pair",
        "element_removal" => "Remove an element of an array literal",
        "endpoint_replacement" => "Swap explicit no-argument first and last",
        "chain_removal" => "Remove one call from a method chain",
        "method_swap" => "Swap a method with its semantic opposite",
        "operand_replacement" => "Replace a binary operation with one operand",
        "interpolation_removal" => "Remove part of an interpolated string",
        "jump_value" => "Replace the value of return, next or break with nil",
        "rescue_removal" => "Remove an exception handler so the error propagates",
        "ensure_removal" => "Remove an ensure clause so its cleanup is skipped",
        "when_removal" => "Remove one when branch of a case",
        "unary_removal" => "Drop a unary minus or bitwise complement",
        "regex_replacement" => "Drop a regex anchor or swap a regex quantifier"
      }.freeze
      POLICY_VERSION = 3
      TIERS = { "all" => DESCRIPTIONS.keys.freeze }.freeze

      def self.list(out, names: [], excluded: [])
        active = select(names, excluded)
        DESCRIPTIONS.each do |name, description|
          out.puts("#{name}  #{active.include?(name) ? 'on' : 'off'}  #{description}  #{OperatorExamples::EXAMPLES.fetch(name)}")
        end
        nil
      end

      def self.policy(names, excluded)
        { "version" => POLICY_VERSION, "selected" => names, "excluded" => excluded,
          "effective" => select(names, excluded) }
      end

      # Exclusion wins over explicit selection; empty exclusions remove nothing.
      def self.select(names, excluded)
        selected = resolve(names)
        excluded.empty? ? selected : selected - resolve(excluded)
      end

      def self.suggestion(name)
        matches = DidYouMean::SpellChecker.new(dictionary: DESCRIPTIONS.keys).correct(name)
        matches.empty? ? "" : "Did you mean #{matches.first}?"
      end

      def self.resolve(names)
        return TIERS.fetch("all") if names.empty?

        legacy = names & %w[core extended]
        unless legacy.empty?
          raise ConfigError, "operator tiers #{legacy.join(', ')} were removed: use concrete names or all; " \
                             "for the old core set exclude range,operator_assignment,condition_negation"
        end
        unknown = names - DESCRIPTIONS.keys - TIERS.keys
        unless unknown.empty?
          raise ConfigError, "unknown operators: #{unknown.join(', ')}. Valid names: " \
                             "#{(DESCRIPTIONS.keys + TIERS.keys).join(', ')}. " \
                             "#{suggestion(unknown.first)} See --list-operators."
        end
        names.flat_map { |name| TIERS.fetch(name) { [name] } }.uniq
      end
    end
  end
end
