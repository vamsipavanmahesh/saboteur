# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"

module Saboteur
  module MutationSource
    # Replaces a binary operation with each of its operands: a + b yields a
    # and b. Arithmetic and comparison calls only; boolean connectors stay
    # with boolean_logic, which already replaces a connector with each side.
    # An operand binds at least as tightly as the operation it replaces, so
    # it needs no parentheses (the re-parse check backs this).
    class OperandReplacement < Base
      FAMILIES = %i[+ - * / % ** < <= > >= == !=].freeze
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "operand_replacement"
      end

      def mutations_for(subject)
        found = []
        visit(subject.node.body, subject, found)
        found
      end

      private

      def visit(node, subject, found)
        return if node.nil? || SCOPE_NODES.any? { |scope| node.is_a?(scope) }

        if node.is_a?(Prism::StatementsNode)
          node.body.each { |statement| visit(statement, subject, found) unless arid?(statement) }
          return
        end

        replace_operands(node, subject, found) if node.is_a?(Prism::CallNode)
        node.compact_child_nodes.each { |child| visit(child, subject, found) }
      end

      def replace_operands(node, subject, found)
        return unless FAMILIES.include?(node.name) && binary?(node)

        [node.receiver, node.arguments.arguments.first].each do |operand|
          edit = Edit.new(file: subject.file, start_byte: node.location.start_offset,
                          end_byte: node.location.end_offset, replacement: operand.slice)
          found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
        end
      end

      def binary?(node)
        node.receiver && node.message_loc && node.call_operator_loc.nil? &&
          node.block.nil?
      end

      def arid?(node)
        @arid.any? { |pattern| pattern.match?(node.slice) }
      end
    end
  end
end
