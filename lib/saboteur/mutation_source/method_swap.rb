# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"

module Saboteur
  module MutationSource
    # Swaps a method whose name has a semantic opposite: min with max,
    # any? with all?, map with each. Only message bytes change; receiver,
    # arguments and block stay intact. A receiver is required, so a bare
    # max(a, b) Kernel call is left alone.
    class MethodSwap < Base
      SWAPS = { min: "max", max: "min", any?: "all?", all?: "any?", map: "each", each: "map" }.freeze
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "method_swap"
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

        swap(node, subject, found) if node.is_a?(Prism::CallNode)
        node.compact_child_nodes.each { |child| visit(child, subject, found) }
      end

      def swap(node, subject, found)
        replacement = SWAPS[node.name]
        return unless replacement && node.receiver && node.message_loc

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
