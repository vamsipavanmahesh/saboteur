# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Drops a unary minus or bitwise complement from an operand: `-x` becomes
    # `x` and `~mask` becomes `mask`. A test that only feeds values where the
    # sign or the complement makes no visible difference cannot tell them
    # apart. `!` stays with negation_removal; unary plus is left alone because
    # it returns numbers unchanged. A negative literal such as `-1` is a
    # number, not an operator call, and belongs to literal_number.
    class UnaryRemoval < Base
      include OperatorVisit

      OPERATORS = %i[-@ ~].freeze

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "unary_removal"
      end

      private

      def mutate_node(node, subject, found)
        return unless node.is_a?(Prism::CallNode) && OPERATORS.include?(node.name) && prefix?(node)

        edit = Edit.new(file: subject.file, start_byte: node.start_offset, end_byte: node.end_offset,
                        replacement: node.receiver.slice)
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
      end

      # The prefix spelling only: x.-@ has a call operator and reads as a call.
      # The prefix form always has a receiver and no arguments.
      def prefix?(node)
        node.call_operator_loc.nil?
      end
    end
  end
end
