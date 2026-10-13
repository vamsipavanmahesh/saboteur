# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "base"

module Saboteur
  module MutationSource
    # Negates the predicate, retaining its evaluation and branch structure.
    class ConditionNegation < Base
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "condition_negation"
      end

      def mutations_for(subject)
        found = []
        visit(subject.node.body, subject, found)
        found
      end

      private

      def visit(node, subject, found)
        return if node.nil? || SCOPE_NODES.any? { |scope| node.is_a?(scope) }
        return if @arid.any? { |pattern| pattern.match?(node.slice) }

        negate(node.predicate, subject, found) if node.is_a?(Prism::IfNode) || node.is_a?(Prism::UnlessNode)
        node.compact_child_nodes.each { |child| visit(child, subject, found) }
      end

      def negate(predicate, subject, found)
        # Existing true/false and negation-removal operators own these cases.
        if predicate.is_a?(Prism::TrueNode) || predicate.is_a?(Prism::FalseNode) || predicate.is_a?(Prism::NilNode)
          return
        end
        return if predicate.is_a?(Prism::CallNode) && predicate.name == :!

        location = predicate.location
        edit = Edit.new(file: subject.file, start_byte: location.start_offset,
                        end_byte: location.end_offset, replacement: "!(#{predicate.slice})")
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
      end
    end
  end
end
