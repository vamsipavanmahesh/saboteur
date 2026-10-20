# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Changes literal values without rebuilding the surrounding source.
    class LiteralReplacement < Base
      include OperatorVisit

      TEXT_NODES = [Prism::InterpolatedStringNode, Prism::SymbolNode, Prism::InterpolatedSymbolNode,
                    Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode,
                    Prism::XStringNode, Prism::InterpolatedXStringNode].freeze
      PARAMETER_NODES = [Prism::ParametersNode, Prism::BlockParametersNode].freeze
      BOUNDARIES = (OperatorVisit::SCOPE_NODES + TEXT_NODES + PARAMETER_NODES).freeze

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "literal_replacement"
      end

      private

      def mutate_node(node, subject, found)
        case node
        when Prism::TrueNode then add(subject, found, node, "literal_boolean", "false")
        when Prism::FalseNode then add(subject, found, node, "literal_boolean", "true")
        when Prism::StringNode then replace_string(node, subject, found)
        end
      end

      def boundary?(node)
        BOUNDARIES.any? { |type| node.is_a?(type) }
      end

      def replace_string(node, subject, found)
        return if node.unescaped.empty?
        return unless node.opening_loc && !node.opening_loc.slice.start_with?("<<")

        add(subject, found, node, "literal_string", '""')
      end

      def add(subject, found, node, operator, replacement)
        edit = Edit.new(file: subject.file, start_byte: node.location.start_offset,
                        end_byte: node.location.end_offset, replacement: replacement)
        found << Mutation.new(subject_id: subject.id, operator: operator, edits: [edit], source: name)
      end
    end
  end
end
