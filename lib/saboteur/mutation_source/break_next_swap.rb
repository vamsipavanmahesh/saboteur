# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Swaps the loop-control keyword: `break` becomes `next` and `next`
    # becomes `break`, keeping any jumped value. A break that ends the loop
    # becomes an iteration skip and the other way round, so only a test that
    # observes the loop's result or side effects can tell them apart.
    # jump_value owns replacing the jumped value with nil.
    class BreakNextSwap < Base
      include OperatorVisit

      SWAP = { Prism::BreakNode => "next", Prism::NextNode => "break" }.freeze

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "break_next_swap"
      end

      private

      def mutate_node(node, subject, found)
        replacement = SWAP[node.class]
        return unless replacement

        location = node.keyword_loc
        edit = Edit.new(file: subject.file, start_byte: location.start_offset,
                        end_byte: location.end_offset, replacement: replacement)
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
      end
    end
  end
end
