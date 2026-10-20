# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"

module Saboteur
  module MutationSource
    # Drops a defensive copy (x.dup, x.clone becomes x) or makes a deep copy
    # shallow (x.deep_dup becomes x.dup). Both let a caller and a callee share
    # state that the original code kept apart.
    class CopyReplacement < Base
      DROPPED = %i[dup clone].freeze
      SHALLOWER = { deep_dup: "dup" }.freeze
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "copy_replacement"
      end

      def mutations_for(subject)
        found = []
        visit(subject.body_node, subject, found)
        found
      end

      private

      def visit(node, subject, found)
        return if node.nil? || SCOPE_NODES.any? { |scope| node.is_a?(scope) }

        if node.is_a?(Prism::StatementsNode)
          node.body.each { |statement| visit(statement, subject, found) unless arid?(statement) }
          return
        end

        replace_copy(node, subject, found) if node.is_a?(Prism::CallNode)
        node.compact_child_nodes.each { |child| visit(child, subject, found) }
        nil
      end

      def replace_copy(node, subject, found)
        return unless node.receiver && node.block.nil? && node.arguments.nil?

        edit = DROPPED.include?(node.name) ? drop(node, subject) : shallow(node, subject)
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name) if edit
      end

      # Receiver stays; the dot (or &.) through the end of the call goes.
      def drop(node, subject)
        Edit.new(file: subject.file, start_byte: node.call_operator_loc.start_offset,
                 end_byte: node.end_offset, replacement: "")
      end

      def shallow(node, subject)
        replacement = SHALLOWER[node.name] or return
        location = node.message_loc
        Edit.new(file: subject.file, start_byte: location.start_offset, end_byte: location.end_offset,
                 replacement: replacement)
      end

      def arid?(node)
        @arid.any? { |pattern| pattern.match?(node.slice) }
      end
    end
  end
end
