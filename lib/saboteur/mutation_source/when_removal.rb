# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Deletes one `when` branch of a case at a time, so its values fall
    # through to the next branch or the else: `when :a then 1` is gone and
    # :a now meets whatever comes after. A test that never takes the branch
    # cannot tell it from its absence. A case keeps at least one `when`,
    # since a case without any does not parse.
    class WhenRemoval < Base
      include OperatorVisit

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "when_removal"
      end

      private

      def mutate_node(node, subject, found)
        return unless node.is_a?(Prism::CaseNode)
        return if node.conditions.one?

        boundaries = node.conditions.map(&:start_offset)
        boundaries << (node.else_clause || node.end_keyword_loc).start_offset
        node.conditions.each_with_index do |branch, index|
          next if heredoc?(branch)

          edit = Edit.new(file: subject.file, start_byte: branch.start_offset,
                          end_byte: boundaries.fetch(index + 1), replacement: "")
          found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
        end
      end

      # A heredoc's body lives on later lines: cutting the branch that opens
      # one would leave the body behind.
      def heredoc?(node)
        node.slice.start_with?("<<") || node.compact_child_nodes.any? { |child| heredoc?(child) }
      end
    end
  end
end
