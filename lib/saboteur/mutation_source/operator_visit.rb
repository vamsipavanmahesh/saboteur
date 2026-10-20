# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"

module Saboteur
  module MutationSource
    # The tree walk shared by the statement-driven operators: visit every
    # node except nested definitions, skip arid statements, and hand each
    # remaining node to the operator's mutate_node hook.
    module OperatorVisit
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

      def mutations_for(subject)
        found = []
        visit(subject.body_node, subject, found)
        found
      end

      private

      def visit(node, subject, found)
        return if node.nil? || boundary?(node)

        if node.is_a?(Prism::StatementsNode)
          node.body.each { |statement| visit(statement, subject, found) unless arid?(statement) }
          return
        end

        mutate_node(node, subject, found)
        node.compact_child_nodes.each { |child| visit(child, subject, found) }
      end

      # Where the walk stops. An operator that also leaves other nodes alone
      # (literal text, parameters) overrides this.
      def boundary?(node)
        SCOPE_NODES.any? { |scope| node.is_a?(scope) }
      end

      def arid?(node)
        @arid.any? { |pattern| pattern.match?(node.slice) }
      end
    end
  end
end
