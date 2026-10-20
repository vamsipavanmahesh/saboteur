# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Replaces the value carried by return, next or break with nil:
    # `return total` becomes `return nil`. A test that only runs the
    # surrounding method without checking what the early exit hands back
    # cannot tell the two apart. statement_removal drops the jump itself
    # and body_nil drops the whole body; neither changes just the value.
    class JumpValue < Base
      include OperatorVisit

      JUMPS = [Prism::ReturnNode, Prism::NextNode, Prism::BreakNode].freeze
      # The caller discards what these return, so a changed value is unobservable.
      IGNORED_RESULT = /\A(initialize|\[\]=|\w+=)\z/

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "jump_value"
      end

      def mutations_for(subject)
        return [] if subject.name.match?(IGNORED_RESULT)

        super
      end

      private

      def mutate_node(node, subject, found)
        return unless JUMPS.any? { |type| node.is_a?(type) }

        arguments = node.arguments
        return if arguments.nil? || arguments.slice == "nil" || heredoc?(arguments)

        # return(a) and return[a] have no space to keep: "returnnil" is another word.
        glued = node.keyword_loc.end_offset == arguments.start_offset
        edit = Edit.new(file: subject.file, start_byte: arguments.start_offset,
                        end_byte: arguments.end_offset, replacement: glued ? " nil" : "nil")
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
      end

      # A heredoc's body lives on later lines: replacing the argument that
      # opens it would leave the body behind.
      def heredoc?(node)
        node.slice.start_with?("<<") || node.compact_child_nodes.any? { |child| heredoc?(child) }
      end
    end
  end
end
