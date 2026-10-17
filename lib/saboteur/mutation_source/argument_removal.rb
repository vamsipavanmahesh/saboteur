# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"

module Saboteur
  module MutationSource
    # Deletes one ordinary argument from a parenthesized method call.
    class ArgumentRemoval < Base
      BOUNDARIES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode,
                    Prism::ParametersNode, Prism::BlockParametersNode].freeze
      EXCLUDED = [Prism::KeywordHashNode, Prism::SplatNode, Prism::ForwardingArgumentsNode].freeze

      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "argument_removal"
      end

      def mutations_for(subject)
        found = []
        tokens = Prism.lex(subject.file_source).value.map(&:first)
        visit(subject.body_node, subject, found, tokens)
        found
      end

      private

      def visit(node, subject, found, tokens)
        return if node.nil? || BOUNDARIES.any? { |type| node.is_a?(type) }

        if node.is_a?(Prism::StatementsNode)
          node.body.each do |child|
            visit(child, subject, found, tokens) unless @arid.any? do |p|
              p.match?(child.slice)
            end
          end
          return
        end
        remove_arguments(node, subject, found, tokens) if node.is_a?(Prism::CallNode)
        node.compact_child_nodes.each { |child| visit(child, subject, found, tokens) }
      end

      def remove_arguments(node, subject, found, tokens)
        return unless node.opening_loc&.slice == "(" && node.arguments

        arguments = node.arguments.arguments
        arguments.each_with_index do |argument, index|
          next if EXCLUDED.any? { |type| argument.is_a?(type) } || heredoc?(argument)

          separator = separator_for(node, arguments, index, tokens)
          edits = [delete(subject, argument.location)]
          edits << delete(subject, separator) if separator
          found << Mutation.new(subject_id: subject.id, operator: name, edits: edits, source: name)
        end
      end

      def separator_for(node, arguments, index, tokens)
        argument = arguments[index]
        after = comma_between(argument.location.end_offset, node.closing_loc.start_offset, tokens)
        return after if after

        previous = arguments[0...index].last
        comma_between(previous.location.end_offset, argument.location.start_offset, tokens) if previous
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
