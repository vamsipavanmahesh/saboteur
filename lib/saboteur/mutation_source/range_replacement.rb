# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "base"

module Saboteur
  module MutationSource
    # Changes whether a range includes its upper endpoint.
    class RangeReplacement < Base
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "range"
      end

      def mutations_for(subject)
        found = []
        visit(subject.body_node, subject, found)
        found
      end

      private

      def visit(node, subject, found)
        return if node.nil? || SCOPE_NODES.any? { |scope| node.is_a?(scope) }
        return if @arid.any? { |pattern| pattern.match?(node.slice) }

        if node.is_a?(Prism::RangeNode) && node.left && node.right
          location = node.operator_loc
          replacement = location.slice == ".." ? "..." : ".."
          edit = Edit.new(file: subject.file, start_byte: location.start_offset,
                          end_byte: location.end_offset, replacement: replacement)
          found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
        end
        node.compact_child_nodes.each { |child| visit(child, subject, found) }
      end
    end
  end
end
