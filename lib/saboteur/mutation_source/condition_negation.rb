# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Negates the predicate, retaining its evaluation and branch structure.
    class ConditionNegation < Base
      include OperatorVisit

      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "condition_negation"
      end

      private

      def mutate_node(node, subject, found)
        negate(node.predicate, subject, found) if node.is_a?(Prism::IfNode) || node.is_a?(Prism::UnlessNode)
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
