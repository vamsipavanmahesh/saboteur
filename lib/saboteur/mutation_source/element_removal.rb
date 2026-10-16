# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "entry_edits"

module Saboteur
  module MutationSource
    # Deletes one element from an array literal.
    class ElementRemoval < Base
      include EntryEdits

      # Nested scopes (a def, a class) are separate subjects; their arrays
      # are not part of the enclosing subject.
      BOUNDARIES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode,
                    Prism::ParametersNode, Prism::BlockParametersNode].freeze

      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        # arid is accepted for parity with the other delegated sources;
        # removing an array element never touches a call receiver.
      end

      def name
        "element_removal"
      end

      # root: the node to walk instead of the subject's method body (a
      # constant's literal, see MutationSource::ConstantLiterals).
      def mutations_for(subject, root: nil)
        found = []
        tokens = Prism.lex(subject.file_source).value.map(&:first)
        visit(root || subject.node.body, subject, found, tokens)
        found
      end

      private

      def visit(node, subject, found, tokens)
        return if node.nil? || BOUNDARIES.any? { |type| node.is_a?(type) }

        if node.is_a?(Prism::StatementsNode)
          node.body.each { |child| visit(child, subject, found, tokens) }
          return
        end
        remove_elements(node, subject, found, tokens) if node.is_a?(Prism::ArrayNode)
        node.compact_child_nodes.each { |child| visit(child, subject, found, tokens) }
      end

      def remove_elements(node, subject, found, tokens)
        elements = node.elements
        elements.each_with_index do |element, index|
          # A splat's separator handling is fragile (`[*A, 2]` vs `[2, *A]`)
          # and removing one can silently change what expands where; leave
          # splats intact, like pair_removal does.
          next if heredoc?(element) || element.is_a?(Prism::SplatNode)

          edits = [delete_entry(subject, element.location)]
          separator = entry_separator(elements, index, ending_for(node), tokens)
          edits << delete_entry(subject, separator) if separator
          found << Mutation.new(subject_id: subject.id, operator: name, edits: edits, source: name)
        end
      end

      def ending_for(node)
        node.closing_loc&.start_offset || node.location.end_offset
      end
    end
  end
end
