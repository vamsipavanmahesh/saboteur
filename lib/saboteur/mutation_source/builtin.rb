# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"

module Saboteur
  module MutationSource
    # The v1 operator set. Every mutation is a byte-range edit of the original
    # file text; nothing is unparsed.
    class Builtin < Base
      DEFAULT_ARID = [
        '\A(puts|pp|p|print|warn)\b',
        '\A(::)?(Rails\.)?logger\b',
        '\A(::)?(StatsD|Statsd|Datadog|NewRelic)\b',
        '\.instrument\b'
      ].freeze

      COMPARISON = {
        :>= => %w[> <=], :> => %w[>= <], :<= => %w[< >=], :< => %w[<= >],
        :== => %w[!=], :!= => %w[==]
      }.freeze
      ARITHMETIC = { :+ => "-", :- => "+", :* => "/", :/ => "*" }.freeze
      BOOLEAN = { "&&" => "||", "||" => "&&", "and" => "or", "or" => "and" }.freeze
      NON_NUMERIC = [Prism::StringNode, Prism::InterpolatedStringNode, Prism::XStringNode,
                     Prism::ArrayNode, Prism::HashNode, Prism::SymbolNode].freeze
      OR_WRITE = [Prism::LocalVariableOrWriteNode, Prism::InstanceVariableOrWriteNode,
                  Prism::ClassVariableOrWriteNode, Prism::GlobalVariableOrWriteNode,
                  Prism::ConstantOrWriteNode, Prism::ConstantPathOrWriteNode,
                  Prism::CallOrWriteNode, Prism::IndexOrWriteNode].freeze
      CATCH_ALL = %w[StandardError ::StandardError Exception ::Exception].freeze
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

      def initialize(arid: DEFAULT_ARID)
        super()
        @arid = arid.map { |pattern| pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern) }
      end

      def name
        "builtin"
      end

      def mutations_for(subject)
        body = subject.node.body
        return [] if body.nil?

        @subject = subject
        @found = []
        coarse(body)
        visit(body)
        @found
      ensure
        @subject = nil
      end

      private

      # --- coarse ---------------------------------------------------------

      def coarse(body)
        statements = body.is_a?(Prism::BeginNode) ? body.statements : body
        return if statements.nil? || statements.body.empty?

        add("body_nil", statements, "nil", coarse: true) unless nothing_to_remove?(statements)
        add("body_raise", statements, "raise", coarse: true) unless statements.slice.strip == "raise" ||
                                                                    rescues_everything?(body)
      end

      # A lone nil, or nothing but logging: replacing it with nil changes nothing.
      def nothing_to_remove?(statements)
        list = statements.body
        (list.size == 1 && list.first.is_a?(Prism::NilNode)) || list.all? { |statement| arid?(statement) }
      end

      # A raise that the method's own rescue catches is absorbed by design. It
      # would survive, and a surviving coarse mutant stops every fine mutant
      # of the method, so it is not generated.
      def rescues_everything?(body)
        clause = body.is_a?(Prism::BeginNode) ? body.rescue_clause : nil
        while clause
          return true if clause.exceptions.empty? || clause.exceptions.any? { |e| CATCH_ALL.include?(e.slice) }

          clause = clause.respond_to?(:subsequent) ? clause.subsequent : clause.consequent
        end
        false
      end

      # --- fine -----------------------------------------------------------

      def visit(node)
        return if node.nil?
        return if SCOPE_NODES.any? { |klass| node.is_a?(klass) }

        if node.is_a?(Prism::StatementsNode)
          visit_statements(node)
          return
        end

        mutate(node)
        node.compact_child_nodes.each { |child| visit(child) }
      end

      # Statement removal applies only to sequences of two or more statements.
      # A single statement is either the whole method body (body_nil covers
      # it) or an expression slot: a ternary branch, an interpolation, the
      # body of a modifier if. Replacing those with nil is not removing a
      # statement and duplicates the condition and coarse operators.
      def visit_statements(node)
        statements = node.body
        statements.each do |statement|
          next if arid?(statement)

          add("statement_removal", statement, "nil") if statements.size > 1 && removable?(statement)
          visit(statement)
        end
      end

      def mutate(node)
        case node
        when Prism::CallNode then mutate_call(node)
        when Prism::AndNode, Prism::OrNode then mutate_boolean(node)
        when Prism::IfNode, Prism::UnlessNode then mutate_condition(node.predicate, hang_on: nil)
        when Prism::WhileNode then mutate_condition(node.predicate, hang_on: "true")
        when Prism::UntilNode then mutate_condition(node.predicate, hang_on: "false")
        when Prism::IntegerNode, Prism::FloatNode then mutate_number(node)
        when *OR_WRITE then add("or_assign", node.operator_loc, "=")
        end
      end

      def mutate_call(node)
        if binary?(node)
          COMPARISON.fetch(node.name, []).each { |op| add("comparison", node.message_loc, op) }
          arithmetic = ARITHMETIC[node.name]
          add("arithmetic", node.message_loc, arithmetic) if arithmetic && numeric_operands?(node)
        end
        mutate_negation(node) if node.name == :! && node.receiver
        add("safe_navigation", node.call_operator_loc, ".") if node.safe_navigation?
      end

      def binary?(node)
        node.receiver && node.message_loc && node.call_operator_loc.nil? &&
          node.arguments&.arguments&.size == 1 && node.block.nil?
      end

      def numeric_operands?(node)
        [node.receiver, node.arguments.arguments.first].none? { |operand| NON_NUMERIC.any? { operand.is_a?(_1) } }
      end

      def mutate_negation(node)
        add("negation_removal", node, node.receiver.slice)
      end

      def mutate_boolean(node)
        replacement = BOOLEAN[node.operator_loc.slice]
        add("boolean_logic", node.operator_loc, replacement) if replacement
      end

      # Replacing a loop condition with the value that never ends it would
      # only produce timeouts, so that one is skipped.
      def mutate_condition(predicate, hang_on:)
        return if predicate.nil?

        %w[true false].each do |literal|
          next if literal == hang_on || predicate.slice == literal

          add("condition_#{literal}", predicate, literal)
        end
      end

      def mutate_number(node)
        value = node.value
        candidates = [value + 1, value - 1, value.zero? ? nil : 0].compact
        candidates.map! { |n| node.is_a?(Prism::FloatNode) ? n.to_f : n }
        candidates.uniq.each do |n|
          next if n == value

          text = n.to_s
          text = "(#{text})" if n.negative?
          add("literal_number", node, text)
        end
      end

      # --- helpers --------------------------------------------------------

      # Removing nil changes nothing. Removing an if/unless without an else
      # is the same mutant as forcing its condition (condition_false /
      # condition_true), so it would only report the same gap twice.
      def removable?(statement)
        case statement
        when Prism::NilNode then false
        when Prism::IfNode then else_branch?(statement, :subsequent)
        when Prism::UnlessNode then else_branch?(statement, :else_clause)
        else true
        end
      end

      def else_branch?(node, name)
        branch = node.respond_to?(name) ? node.public_send(name) : node.consequent
        !branch.nil?
      end

      def arid?(node)
        source = node.slice
        @arid.any? { |pattern| pattern.match?(source) }
      end

      def add(operator, node_or_location, replacement, coarse: false)
        return if node_or_location.nil?

        location = node_or_location.respond_to?(:location) ? node_or_location.location : node_or_location
        return if location.slice == replacement

        edit = Edit.new(file: @subject.file, start_byte: location.start_offset,
                        end_byte: location.end_offset, replacement: replacement)
        @found << Mutation.new(subject_id: @subject.id, operator: operator, edits: [edit],
                               coarse: coarse, source: name)
      end
    end
  end
end
