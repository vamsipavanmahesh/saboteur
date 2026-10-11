# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"

module Saboteur
  module MutationSource
    # Swaps the inclusion rule of a filter call with its exclusion rule.
    # Only message bytes change; arguments, receiver and block stay intact.
    class FilterReplacement < Base
      REPLACEMENTS = { select: "reject", reject: "select", select!: "reject!", reject!: "select!" }.freeze
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

      def initialize(arid: [])
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "filter_replacement"
      end

      def mutations_for(subject)
        found = []
        visit(subject.node.body, subject, found)
        found
      end

      private

      def visit(node, subject, found)
        return if node.nil? || SCOPE_NODES.any? { |scope| node.is_a?(scope) }

        if node.is_a?(Prism::StatementsNode)
          node.body.each { |statement| visit(statement, subject, found) unless arid?(statement) }
          return
        end

        replace_filter(node, subject, found) if node.is_a?(Prism::CallNode)
        node.compact_child_nodes.each { |child| visit(child, subject, found) }
      end

      def replace_filter(node, subject, found)
        replacement = REPLACEMENTS[node.name]
        return unless replacement && node.receiver && node.block
        return unless node.arguments.nil?

        location = node.message_loc
        edit = Edit.new(file: subject.file, start_byte: location.start_offset,
                        end_byte: location.end_offset, replacement: replacement)
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
      end

      def arid?(node)
        @arid.any? { |pattern| pattern.match?(node.slice) }
      end
    end
  end
end
