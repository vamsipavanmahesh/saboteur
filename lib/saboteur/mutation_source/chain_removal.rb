# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"

module Saboteur
  module MutationSource
    # Drops one link from the middle of a method chain: a.b.c becomes a.c.
    # The first receiver and the last call stay, so the result is still a call
    # on the original object.
    class ChainRemoval < Base
      BOUNDARIES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze
      # Links this operator leaves alone by design. They hand back their receiver or a
      # copy of it (tap after running a block), so dropping one changes mutability,
      # copying or a block's side effects. Tests can observe those, but they are other
      # contracts than "a step in the query chain went missing", and removing them
      # mostly yields noise, so they are out of scope here.
      IDENTITY_CALLS = %w[freeze dup clone itself tap].freeze

      # Targets of a write: `a.b.c = 1`, `a.b.c += 1`, `a.b[0] ||= 1`. The whole receiver chain
      # is the thing being assigned to, so no link of it is dropped.
      WRITE_NODES = [Prism::CallOperatorWriteNode, Prism::CallOrWriteNode, Prism::CallAndWriteNode,
                     Prism::IndexOperatorWriteNode, Prism::IndexOrWriteNode, Prism::IndexAndWriteNode].freeze

      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "chain_removal"
      end

      def mutations_for(subject)
        found = []
        visit(subject.body_node, subject, found)
        found
      end

      private

      def visit(node, subject, found)
        return if node.nil? || BOUNDARIES.any? { |type| node.is_a?(type) }

        if node.is_a?(Prism::StatementsNode)
          node.body.each { |child| visit(child, subject, found) unless @arid.any? { |p| p.match?(child.slice) } }
          return
        end
        remove_link(node, subject, found) if node.is_a?(Prism::CallNode)
        children(node).each { |child| visit(child, subject, found) }
      end

      # Everything under the node except the receiver chain of a write target.
      def children(node)
        return node.compact_child_nodes unless write_target?(node)

        node.compact_child_nodes.reject { |child| child.equal?(node.receiver) }
      end

      def write_target?(node)
        WRITE_NODES.any? { |type| node.is_a?(type) } || (node.is_a?(Prism::CallNode) && node.attribute_write?)
      end

      def remove_link(call, subject, found)
        link = call.receiver
        return unless call.call_operator_loc && !call.attribute_write? && removable?(link)

        edit = Edit.new(file: subject.file, start_byte: link.receiver.end_offset,
                        end_byte: link.end_offset, replacement: "")
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
      end

      # A dotted call with a method name (a dot always has a receiver).
      def removable?(link)
        link.is_a?(Prism::CallNode) && link.call_operator_loc && link.message_loc &&
          !IDENTITY_CALLS.include?(link.name.to_s)
      end
    end
  end
end
