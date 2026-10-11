# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"

module Saboteur
  module MutationSource
    # Deletes one association from a hash literal or keyword argument list.
    class PairRemoval < Base
      BOUNDARIES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode,
                    Prism::ParametersNode, Prism::BlockParametersNode].freeze

      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "pair_removal"
      end

      def mutations_for(subject)
        found = []
        tokens = Prism.lex(subject.file_source).value.map(&:first)
        visit(subject.node.body, subject, found, tokens)
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

          edits = [delete(subject, pair.location)]
          separator = separator_for(node, pairs, index, tokens, call)
          edits << delete(subject, separator) if separator
          found << Mutation.new(subject_id: subject.id, operator: name, edits: edits, source: name)
        end
      end

      def separator_for(node, pairs, index, tokens, call)
        pair = pairs[index]
        ending = ending_for(node, call)
        after = comma_between(pair.location.end_offset, ending, tokens)
        return after if after

        previous = pairs[0...index].last
        previous ||= call.arguments.arguments[0...-1].last if call
        comma_between(previous.location.end_offset, pair.location.start_offset, tokens) if previous
      end

      def ending_for(node, call)
        return node.closing_loc.start_offset if node.is_a?(Prism::HashNode)
        return call.closing_loc.start_offset if call.closing_loc
        return call.block.location.start_offset if call.block

        node.location.end_offset
      end

      def comma_between(first, last, tokens)
        tokens.find do |token|
          token.type == :COMMA && token.location.start_offset >= first && token.location.end_offset <= last
        end&.location
      end

      def heredoc?(node)
        (node.respond_to?(:opening_loc) && node.opening_loc&.slice&.start_with?("<<")) ||
          node.compact_child_nodes.any? { |child| heredoc?(child) }
      end

      def delete(subject, location)
        Edit.new(file: subject.file, start_byte: location.start_offset, end_byte: location.end_offset, replacement: "")
      end
    end
  end
end
