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
      # Calls that return an equal object, so removing them changes nothing a test can see.
      IDENTITY_CALLS = %w[freeze dup clone itself tap].freeze

      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "chain_removal"
      end

      def mutations_for(subject)
        found = []
        visit(subject.node.body, subject, found)
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
        node.compact_child_nodes.each { |child| visit(child, subject, found) }
      end

      def remove_link(call, subject, found)
        link = call.receiver
        return unless call.call_operator_loc && removable?(link)

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
