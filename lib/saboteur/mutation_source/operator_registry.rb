# SPDX-License-Identifier: MIT
# frozen_string_literal: true

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
        "safe_navigation" => "Replace safe navigation with a regular call",
        "statement_removal" => "Replace a statement with nil",
        "filter_replacement" => "Swap select and reject",
        "literal_string" => "Empty a string literal",
        "literal_boolean" => "Swap a boolean literal",
        "argument_removal" => "Remove a call argument",
        "pair_removal" => "Remove a hash pair",
        "endpoint_replacement" => "Swap explicit no-argument first and last",
        "chain_removal" => "Remove one call from a method chain"
      }.freeze
      EXTENDED = %w[range operator_assignment condition_negation].freeze
      TIERS = { "core" => (DESCRIPTIONS.keys - EXTENDED).freeze, "extended" => EXTENDED,
                "all" => DESCRIPTIONS.keys.freeze }.freeze

      def self.list(out)
        DESCRIPTIONS.each do |name, description|
          out.puts("#{name}  #{EXTENDED.include?(name) ? 'extended' : 'core'}  #{description}")
        end
        nil
      end

      def self.resolve(names)
        return TIERS.fetch("core") if names.empty?

        unknown = names - DESCRIPTIONS.keys - TIERS.keys
        unless unknown.empty?
          raise ConfigError, "unknown operators: #{unknown.join(', ')}. Valid names: " \
                             "#{(DESCRIPTIONS.keys + TIERS.keys).join(', ')}"
        end
        names.flat_map { |name| TIERS.fetch(name) { [name] } }.uniq
      end
    end
  end
end
