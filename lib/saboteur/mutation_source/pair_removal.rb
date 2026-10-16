# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "entry_edits"

module Saboteur
  module MutationSource
    # Deletes one association from a hash literal or keyword argument list.
    class PairRemoval < Base
      include EntryEdits

      BOUNDARIES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode,
                    Prism::ParametersNode, Prism::BlockParametersNode].freeze

      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "pair_removal"
      end

      # root: the node to walk instead of the subject's method body (a
      # constant's literal, see MutationSource::ConstantLiterals).
      def mutations_for(subject, root: nil)
        found = []
        tokens = Prism.lex(subject.file_source).value.map(&:first)
        visit(root || subject.node.body, subject, found, tokens)
        found
      end

      private

      def visit(node, subject, found, tokens)
        return if node.nil? || BOUNDARIES.any? { |type| node.is_a?(type) }

        if node.is_a?(Prism::StatementsNode)
          node.body.each do |child|
            visit(child, subject, found, tokens) unless @arid.any? { |p| p.match?(child.slice) }
          end
          return
        end
        remove_pairs(node, subject, found, tokens) if node.is_a?(Prism::HashNode)
        remove_keywords(node, subject, found, tokens) if node.is_a?(Prism::CallNode)
        node.compact_child_nodes.each { |child| visit(child, subject, found, tokens) }
      end

      def remove_keywords(node, subject, found, tokens)
        return unless node.arguments

        node.arguments.arguments.grep(Prism::KeywordHashNode).each do |hash|
          remove_pairs(hash, subject, found, tokens, call: node)
        end
      end

      def remove_pairs(node, subject, found, tokens, call: nil)
        pairs = node.elements
        pairs.each_with_index do |pair, index|
          next unless pair.is_a?(Prism::AssocNode)
          next if heredoc?(pair)

          edits = [delete_entry(subject, pair.location)]
          # Removing the first keyword argument may need the comma after the
          # call's last positional argument.
          before = call.arguments.arguments[0...-1].last if call
          separator = entry_separator(pairs, index, ending_for(node, call), tokens, before: before)
          edits << delete_entry(subject, separator) if separator
          found << Mutation.new(subject_id: subject.id, operator: name, edits: edits, source: name)
        end
      end

      def ending_for(node, call)
        return node.closing_loc.start_offset if node.is_a?(Prism::HashNode)
        return call.closing_loc.start_offset if call.closing_loc
        return call.block.location.start_offset if call.block

        node.location.end_offset
      end
    end
  end
end
