# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"

module Saboteur
  module MutationSource
    # Changes literal values without rebuilding the surrounding source.
    class LiteralReplacement < Base
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze
      TEXT_NODES = [Prism::InterpolatedStringNode, Prism::SymbolNode, Prism::InterpolatedSymbolNode,
                    Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode,
                    Prism::XStringNode, Prism::InterpolatedXStringNode].freeze
      PARAMETER_NODES = [Prism::ParametersNode, Prism::BlockParametersNode].freeze
      BOUNDARIES = (SCOPE_NODES + TEXT_NODES + PARAMETER_NODES).freeze

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "literal_replacement"
      end

      def mutations_for(subject)
        found = []
        visit(subject.node.body, subject, found)
        found
      end

      private

      def visit(node, subject, found)
        return if node.nil? || boundary?(node)

        if node.is_a?(Prism::StatementsNode)
          node.body.each { |statement| visit(statement, subject, found) unless arid?(statement) }
          return
        end

        case node
        when Prism::TrueNode then add(subject, found, node, "literal_boolean", "false")
        when Prism::FalseNode then add(subject, found, node, "literal_boolean", "true")
        when Prism::StringNode
          replace_string(node, subject, found)
        end
        node.compact_child_nodes.each { |child| visit(child, subject, found) }
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

      def arid?(node)
        @arid.any? { |pattern| pattern.match?(node.slice) }
      end
    end
  end
end
