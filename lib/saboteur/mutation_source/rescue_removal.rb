# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Deletes one exception handler at a time, so the error it caught
    # propagates instead: a `rescue` clause of a begin block or method body,
    # or the `rescue value` tail of a modifier. A test that never makes the
    # guarded code raise cannot tell the handler from no handler. Removing a
    # handler's statements is statement_removal's job; this removes the
    # handler itself.
    class RescueRemoval < Base
      include OperatorVisit

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "rescue_removal"
      end

      private

      def mutate_node(node, subject, found)
        case node
        when Prism::BeginNode then remove_clauses(node, subject, found)
        when Prism::RescueModifierNode then remove_modifier(node, subject, found)
        end
      end

      # A clause's location runs through the clauses after it, so its own
      # text ends where the next one starts. `else` without a rescue is a
      # syntax error, so the only handler of a begin with an else stays.
      def remove_clauses(node, subject, found)
        clause = node.rescue_clause
        return if clause&.subsequent.nil? && node.else_clause

        while clause
          finish = clause.subsequent ? clause.subsequent.start_offset : clause.end_offset
          add(subject, found, clause.start_offset, finish) unless heredoc?(clause)
          clause = clause.subsequent
        end
      end

      def remove_modifier(node, subject, found)
        return if heredoc?(node.rescue_expression)

        add(subject, found, node.expression.end_offset, node.end_offset)
      end

      def add(subject, found, start_byte, end_byte)
        edit = Edit.new(file: subject.file, start_byte: start_byte, end_byte: end_byte, replacement: "")
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
      end

      # A heredoc's body lives on later lines: cutting the handler that opens
      # one would leave the body behind.
      def heredoc?(node)
        node.slice.start_with?("<<") || node.compact_child_nodes.any? { |child| heredoc?(child) }
      end
    end
  end
end
