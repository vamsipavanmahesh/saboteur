# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Swaps a method whose name has a semantic opposite: min with max,
    # any? with all?, map with each. Only message bytes change; receiver,
    # arguments and block stay intact. A receiver is required, so a bare
    # max(a, b) Kernel call is left alone.
    class MethodSwap < Base
      include OperatorVisit

      SWAPS = { min: "max", max: "min", any?: "all?", all?: "any?", map: "each", each: "map" }.freeze

      # Node types that mix used and discarded child positions get a named
      # handler; anything not listed here is conservative: every child's
      # value is treated as used (#440).
      CONTAINER_HANDLERS = {
        Prism::StatementsNode => :visit_statements,
        Prism::IfNode => :visit_if,
        Prism::UnlessNode => :visit_unless,
        Prism::ElseNode => :visit_else,
        Prism::EnsureNode => :visit_ensure,
        Prism::CaseNode => :visit_case,
        Prism::CaseMatchNode => :visit_case,
        Prism::WhenNode => :visit_when,
        Prism::InNode => :visit_in,
        Prism::BeginNode => :visit_begin,
        Prism::RescueNode => :visit_rescue,
        Prism::WhileNode => :visit_loop,
        Prism::UntilNode => :visit_loop
      }.freeze

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
        @discard_depth = 0
      end

      def name
        "method_swap"
      end

      private

      # Overrides OperatorVisit#visit to track positions whose value is
      # provably discarded: a non-last statement, and - recursing from a
      # discarded statement - the tail expression of each branch of an
      # if/elsif/else/unless/case/when, a begin/rescue body, or a
      # while/until body (a loop's value never observes its body), or an
      # ensure body (its value never contributes to the result). each
      # and map differ only in their return value (both run the block the
      # same way), so swapping them in a discarded-value position yields
      # an equivalent mutant (#399, #440). A call whose value flows into
      # a predicate, receiver, block result, or control-flow argument
      # (return/break/next) is used and stays swappable, as is the whole
      # body of a def or block. A lazy receiver breaks the equivalence:
      # lazy.map defers the block, so discarding it runs nothing (#431).
      def visit(node, subject, found)
        return if node.nil? || OperatorVisit::SCOPE_NODES.any? { |scope| node.is_a?(scope) }

        handler = CONTAINER_HANDLERS[node.class]
        handler ? send(handler, node, subject, found) : visit_used_children(node, subject, found)
      end

      # Non-last statements are discarded-value positions; the last
      # statement inherits the surrounding context (#399).
      def visit_statements(node, subject, found)
        node.body.each_with_index do |statement, index|
          next if arid?(statement)

          if index < node.body.size - 1
            discarded { visit(statement, subject, found) }
          else
            visit(statement, subject, found)
          end
        end
      end

      def visit_else(node, subject, found)
        visit(node.statements, subject, found)
      end

      # An ensure body's value never contributes to the result, so it is
      # always a discarded-value position (#440).
      def visit_ensure(node, subject, found)
        discarded { visit(node.statements, subject, found) }
      end

      def visit_in(node, subject, found)
        used { visit(node.pattern, subject, found) }
        visit(node.statements, subject, found)
      end

      def visit_if(node, subject, found)
        visit_branch(node, subject, found, :subsequent)
      end

      def visit_unless(node, subject, found)
        visit_branch(node, subject, found, :else_clause)
      end

      # Branch bodies inherit the discard context; the predicate's value
      # selects the branch, so it is always used (#440).
      def visit_branch(node, subject, found, else_reader)
        used { visit(node.predicate, subject, found) }
        visit(node.statements, subject, found)
        visit(node.public_send(else_reader), subject, found)
      end

      def visit_case(node, subject, found)
        used { visit(node.predicate, subject, found) }
        node.conditions.each { |condition| visit(condition, subject, found) }
        visit(node.else_clause, subject, found)
      end

      def visit_when(node, subject, found)
        node.conditions.each { |condition| used { visit(condition, subject, found) } }
        visit(node.statements, subject, found)
      end

      def visit_begin(node, subject, found)
        visit(node.statements, subject, found)
        visit(node.rescue_clause, subject, found)
        visit(node.else_clause, subject, found)
        discarded { visit(node.ensure_clause, subject, found) }
      end

      def visit_rescue(node, subject, found)
        node.exceptions.each { |exception| used { visit(exception, subject, found) } }
        visit(node.statements, subject, found)
        visit(node.subsequent, subject, found)
      end

      # A loop's value never observes its body, so the body is always a
      # discarded-value position (#440).
      def visit_loop(node, subject, found)
        used { visit(node.predicate, subject, found) }
        discarded { visit(node.statements, subject, found) }
      end

      # Default: every child's value is consumed by its parent.
      def visit_used_children(node, subject, found)
        mutate_node(node, subject, found)
        node.compact_child_nodes.each { |child| used { visit(child, subject, found) } }
      end

      # Marks value-discarded positions during the walk. `used` resets the
      # depth where a child's value is consumed by its parent.
      def discarded
        @discard_depth += 1
        yield
      ensure
        @discard_depth -= 1
      end

      def used
        depth = @discard_depth
        @discard_depth = 0
        yield
      ensure
        @discard_depth = depth
      end

      # Any `.lazy` in the receiver chain, syntactically.
      def lazy_receiver?(node)
        node = node.receiver while node.is_a?(Prism::CallNode) && node.name != :lazy
        node.is_a?(Prism::CallNode)
      end

      def mutate_node(node, subject, found)
        swap(node, subject, found) if node.is_a?(Prism::CallNode)
      end

      def swap(node, subject, found)
        replacement = SWAPS[node.name]
        return unless replacement && node.receiver
        return if @discard_depth.positive? && %w[each map].include?(node.name.to_s) && !lazy_receiver?(node.receiver)

        location = node.message_loc
        edit = Edit.new(file: subject.file, start_byte: location.start_offset,
                        end_byte: location.end_offset, replacement: replacement)
        found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
      end
    end
  end
end
