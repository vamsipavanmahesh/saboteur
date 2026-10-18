# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Swap two explicit positional arguments without moving their separators.
    # Order-insensitive calls (includes, attr_reader, validates) can be equivalent; arid patterns can exclude them.
    class ArgumentSwap < Base
      include OperatorVisit

      EXCLUDED = [Prism::KeywordHashNode, Prism::SplatNode, Prism::ForwardingArgumentsNode].freeze

      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "argument_swap"
      end

      private

      def mutate_node(node, subject, found)
        return unless node.is_a?(Prism::CallNode) && node.opening_loc&.slice == "("

        arguments = node.arguments&.arguments
        return unless arguments&.size == 2
        return if arguments.any? { |argument| excluded?(argument) }

        left, right = arguments
        return if left.slice == right.slice

        # Prism forwards location offsets on nodes; removing .location here is equivalent.
        edits = [[left, right], [right, left]].map do |original, replacement|
          Edit.new(file: subject.file, start_byte: original.location.start_offset,
                   end_byte: original.location.end_offset, replacement: replacement.slice)
        end
        found << Mutation.new(subject_id: subject.id, operator: name, edits: edits, source: name)
      end

      def excluded?(argument)
        EXCLUDED.any? { |type| argument.is_a?(type) } || heredoc?(argument)
      end

      def heredoc?(node)
        (node.respond_to?(:opening_loc) && node.opening_loc&.slice&.start_with?("<<")) ||
          node.compact_child_nodes.any? { |child| heredoc?(child) }
      end
    end
  end
end
