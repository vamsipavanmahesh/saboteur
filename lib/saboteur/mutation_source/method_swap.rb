# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Swaps a method whose name has a semantic opposite: min with max,
    # any? with all?, map with each. Only message bytes change; receiver,
    # arguments and block stay intact. A receiver is required, so a bare
    # max(a, b) Kernel call is left alone.
    class MethodSwap < Base
      include OperatorVisit

      SWAPS = { min: "max", max: "min", any?: "all?", all?: "any?", map: "each", each: "map" }.freeze

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "method_swap"
      end

      private

      # Overrides OperatorVisit#visit to learn which calls stand as a
      # non-last statement: their return value is provably discarded. each
      # and map differ only in that value (both run the block the same way),
      # so swapping them there yields an equivalent mutant (#399). The last
      # statement is the body's value and stays swappable, as does any call
      # nested inside an expression.
      def visit(node, subject, found)
        return super unless node.is_a?(Prism::StatementsNode)

        node.body.each_with_index do |statement, index|
          next if arid?(statement)

          @discarded = statement if index < node.body.size - 1
          visit(statement, subject, found)
          @discarded = nil
        end
      end

      def mutate_node(node, subject, found)
        swap(node, subject, found) if node.is_a?(Prism::CallNode)
      end

      def swap(node, subject, found)
        replacement = SWAPS[node.name]
        return unless replacement && node.receiver
        return if node.equal?(@discarded) && %w[each map].include?(node.name.to_s)

        location = node.message_loc
        edit = Edit.new(file: subject.file, start_byte: location.start_offset,
                        end_byte: location.end_offset, replacement: replacement)
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
      end
    end
  end
end
