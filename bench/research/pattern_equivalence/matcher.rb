# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"

module PatternEquivalence
  # Research candidates only. No verdict is sufficient to skip execution.
  # Source/TracePoint observability remains outside these syntactic identities.
  class Matcher
    def classify(subject, mutation)
      changed = subject.apply(mutation.edits)
      return "P0_noop" if changed == subject.source
      return nil unless mutation.operator == "boolean_logic" && mutation.edits.size == 1

      edit = mutation.edits.first
      node = matching_node(subject.node.body, edit)
      return nil unless node.is_a?(Prism::AndNode) || node.is_a?(Prism::OrNode)

      identity = (node.is_a?(Prism::AndNode) && node.left.is_a?(Prism::TrueNode)) ||
                 (node.is_a?(Prism::OrNode) && node.left.is_a?(Prism::FalseNode))
      "P6_left_identity" if identity && edit.replacement == node.right.slice
    end

    private

    def matching_node(node, edit)
      return nil unless node
      return node if (node.is_a?(Prism::AndNode) || node.is_a?(Prism::OrNode)) &&
                     node.location.start_offset == edit.start_byte && node.location.end_offset == edit.end_byte

      node.compact_child_nodes.each do |child|
        found = matching_node(child, edit)
        return found if found
      end
      nil
    end
  end
end
