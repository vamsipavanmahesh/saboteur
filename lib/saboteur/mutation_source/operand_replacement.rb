# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Replaces a binary operation with each of its operands: a + b yields a
    # and b. Arithmetic and comparison calls only; boolean connectors stay
    # with boolean_logic, which already replaces a connector with each side.
    # An operand binds at least as tightly as the operation it replaces, so
    # it needs no parentheses (the re-parse check backs this).
    class OperandReplacement < Base
      include OperatorVisit

      FAMILIES = %i[+ - * / % ** < <= > >= == !=].freeze

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "operand_replacement"
      end

      private

      def mutate_node(node, subject, found)
        replace_operands(node, subject, found) if node.is_a?(Prism::CallNode)
      end

      def replace_operands(node, subject, found)
        return unless FAMILIES.include?(node.name) && binary?(node)

        [node.receiver, *node.arguments.arguments].each do |operand|
          edit = Edit.new(file: subject.file, start_byte: node.start_offset,
                          end_byte: node.end_offset, replacement: operand.slice)
          found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
        end
      end

      # Only the infix spelling is binary: an operator call has no call
      # operator, and its receiver, message, single argument and lack of a
      # block all follow from that (a block binds to the last operand's own
      # call, never to the operator).
      def binary?(node)
        node.call_operator_loc.nil?
      end
    end
  end
end
