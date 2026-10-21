# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Inserts a unary operator before one operand at a time (the classic UOI
    # operator from the mutation-testing literature): `!` before an operand
    # of && or ||, `-` before an operand of an arithmetic call. Only leaf
    # operands (variables, instance variables, calls) are touched: literals
    # belong to the literal operators, a bare predicate to condition_negation,
    # and an operand that already carries a unary operator is left alone.
    class UnaryInsertion < Base
      include OperatorVisit

      ARITHMETIC = %i[+ - * / % **].freeze
      LEAVES = [Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::CallNode].freeze

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "unary_insertion"
      end

      def mutations_for(subject)
        super.sort_by do |mutation|
          edit, = mutation.edits
          edit.start_byte
        end
      end

      private

      def mutate_node(node, subject, found)
        if node.is_a?(Prism::AndNode) || node.is_a?(Prism::OrNode)
          insert_before(node.left, "!", subject, found)
          insert_before(node.right, "!", subject, found)
        elsif arithmetic?(node)
          argument, = node.arguments.arguments
          # A chained arithmetic receiver is visited on its own and inserts at
          # the same first byte, so emitting here would duplicate that edit.
          insert_before(node.receiver, "-", subject, found) unless arithmetic?(node.receiver)
          insert_before(argument, "-", subject, found)
        end
      end

      def arithmetic?(node)
        node.is_a?(Prism::CallNode) && ARITHMETIC.include?(node.name) && node.call_operator_loc.nil? &&
          !string_concat?(node)
      end

      # A binary call with a String (or interpolated String) on either side is
      # concatenation, not arithmetic, and unary - on a String keeps the same
      # characters, so no example asserting the value could kill that mutant.
      def string_concat?(node)
        argument, = node.arguments.arguments
        stringish?(node.receiver) || stringish?(argument)
      end

      def stringish?(node)
        if node.is_a?(Prism::StringNode) || node.is_a?(Prism::InterpolatedStringNode)
          true
        elsif node.is_a?(Prism::CallNode) && node.name == :+ && node.call_operator_loc.nil?
          argument, = node.arguments.arguments
          stringish?(node.receiver) || stringish?(argument)
        else
          false
        end
      end

      def insert_before(operand, operator, subject, found)
        return unless LEAVES.any? { |leaf| operand.is_a?(leaf) }
        return if unary_call?(operand)
        return if operand.is_a?(Prism::CallNode) && operand.block

        edit = Edit.new(file: subject.file, start_byte: operand.start_offset, end_byte: operand.start_offset,
                        replacement: operator)
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
      end

      # !x, -x, ~x already carry the operator family being inserted; adding
      # another only flips the sign or truthiness back.
      def unary_call?(operand)
        operand.is_a?(Prism::CallNode) && %i[! -@ ~].include?(operand.name) && operand.call_operator_loc.nil?
      end
    end
  end
end
