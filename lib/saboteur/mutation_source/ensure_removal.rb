# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Deletes the `ensure` clause of a begin block, method body or do block, so
    # the cleanup it runs is skipped: `begin; x; ensure; y; end` becomes
    # `begin; x; end`. A test that never checks the cleanup cannot tell the
    # clause from no clause. Removing the clause's statements is
    # statement_removal's job; this removes the clause itself. A rescue or
    # else clause beside it stays.
    class EnsureRemoval < Base
      include OperatorVisit

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "ensure_removal"
      end

      private

      def mutate_node(node, subject, found)
        return unless node.is_a?(Prism::BeginNode)

        clause = node.ensure_clause
        return if clause.nil? || heredoc?(clause)

        # The clause's location runs through the closing `end`, which stays.
        edit = Edit.new(file: subject.file, start_byte: clause.start_offset,
                        end_byte: clause.end_keyword_loc.start_offset, replacement: "")
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
      end

      # A heredoc's body lives on later lines: cutting the clause that opens
      # one would leave the body behind.
      def heredoc?(node)
        node.slice.start_with?("<<") || node.compact_child_nodes.any? { |child| heredoc?(child) }
      end
    end
  end
end
