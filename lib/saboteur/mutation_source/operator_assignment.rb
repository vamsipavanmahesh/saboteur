# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "base"

module Saboteur
  module MutationSource
    # Changes the arithmetic operation, without changing the assignment target.
    class OperatorAssignment < Base
      REPLACEMENTS = { :+ => "-=", :- => "+=", :* => "/=", :/ => "*=" }.freeze
      WRITE_NODES = [Prism::LocalVariableOperatorWriteNode, Prism::InstanceVariableOperatorWriteNode,
                     Prism::ClassVariableOperatorWriteNode, Prism::GlobalVariableOperatorWriteNode,
                     Prism::ConstantOperatorWriteNode, Prism::ConstantPathOperatorWriteNode,
                     Prism::CallOperatorWriteNode, Prism::IndexOperatorWriteNode].freeze
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "operator_assignment"
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

        replace(node, subject, found) if WRITE_NODES.any? { |type| node.is_a?(type) }
        node.compact_child_nodes.each { |child| visit(child, subject, found) }
      end

      def replace(node, subject, found)
        replacement = REPLACEMENTS[node.binary_operator]
        return unless replacement

        location = node.binary_operator_loc
        edit = Edit.new(file: subject.file, start_byte: location.start_offset,
                        end_byte: location.end_offset, replacement: replacement)
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
      end
    end
  end
end
