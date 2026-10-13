# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "filter_replacement"
require_relative "literal_replacement"
require_relative "argument_removal"
require_relative "pair_removal"
require_relative "endpoint_replacement"
require_relative "operator_registry"

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

      # A comparison replacement: swap the operator, or put a literal in
      # place of the whole comparison.
      Swap = Data.define(:operator)
      Literal = Data.define(:text)

      # Sufficient relational replacements (Kaminski, Ammann, Offutt 2011):
      # the others are subsumed by these. For == and != Ruby gets true/false:
      # <= and >= raise on objects that are not Comparable, which only gives
      # cheap crash kills.
      COMPARISON = {
        :< => [Swap["<="], Swap["!="], Literal["false"]], :<= => [Swap["<"], Swap["=="], Literal["true"]],
        :> => [Swap[">="], Swap["!="], Literal["false"]], :>= => [Swap[">"], Swap["=="], Literal["true"]],
        :== => [Literal["false"], Literal["true"]], :!= => [Literal["true"], Literal["false"]]
      }.freeze
      ARITHMETIC = { :+ => "-", :- => "+", :* => "/", :/ => "*" }.freeze
      # Sufficient connector replacements (Just et al. 2012): each operand
      # alone, then the constant the connector cannot produce from it.
      ABSORBING = { "&&" => "false", "and" => "false", "||" => "true", "or" => "true" }.freeze
      NON_NUMERIC = [Prism::StringNode, Prism::InterpolatedStringNode, Prism::XStringNode,
                     Prism::ArrayNode, Prism::HashNode, Prism::SymbolNode].freeze
      OR_WRITE = [Prism::LocalVariableOrWriteNode, Prism::InstanceVariableOrWriteNode,
                  Prism::ClassVariableOrWriteNode, Prism::GlobalVariableOrWriteNode,
                  Prism::ConstantOrWriteNode, Prism::ConstantPathOrWriteNode,
                  Prism::CallOrWriteNode, Prism::IndexOrWriteNode].freeze
      CATCH_ALL = %w[StandardError ::StandardError Exception ::Exception].freeze
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

      def initialize(arid: DEFAULT_ARID, operators: [])
        super()
        @operators = OperatorRegistry.resolve(operators)
        @arid = arid.map { |pattern| pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern) }
        @filter_replacement = FilterReplacement.new(arid: arid)
        @literal_replacement = LiteralReplacement.new(arid: arid)
        @argument_removal = ArgumentRemoval.new(arid: arid)
        @pair_removal = PairRemoval.new(arid: arid)
        @endpoint_replacement = EndpointReplacement.new(arid: arid)
      end

      def name
        "builtin"
      end

      def mutations_for(subject)
        body = subject.node.body
        @subject = subject
        @found = []
        coarse(body)
        visit(body)
        @found.concat(@filter_replacement.mutations_for(subject))
        @found.concat(@literal_replacement.mutations_for(subject))
        @found.concat(@argument_removal.mutations_for(subject))
        @found.concat(@pair_removal.mutations_for(subject))
        @found.concat(@endpoint_replacement.mutations_for(subject))
        @found.select { |mutation| @operators.include?(mutation.operator) }
      ensure
        @subject = nil
      end

      private

      # --- coarse ---------------------------------------------------------

      def coarse(body)
        statements = body.is_a?(Prism::BeginNode) ? body.statements : body
        return if statements.nil?

        unless nothing_to_remove?(statements)
          # A predicate's nil is just false; true is the value its tests must reject.
          (@subject.name.end_with?("?") ? %w[true false] : %w[nil]).each do |value|
            add("body_#{value}", statements, value, coarse: true)
          end
        end
        add("body_raise", statements, "raise", coarse: true) unless rescues_everything?(body)
      end

      # Nothing but logging: replacing it changes nothing a test can see.
      def nothing_to_remove?(statements)
        statements.body.all? { |statement| arid?(statement) }
      end

      # A raise that the method's own rescue catches is absorbed by design. It
      # is not generated: rejecting that exception is not the rescue contract.
      # Fine mutants still run regardless of the coarse verdicts.
      def rescues_everything?(body)
        clause = body.is_a?(Prism::BeginNode) ? body.rescue_clause : nil
        while clause
          return true if clause.exceptions.empty? || clause.exceptions.any? { |e| CATCH_ALL.include?(e.slice) }

          clause = clause.subsequent
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

          removable_here = statements.drop(1).any? && removable?(statement)
          add("statement_removal", statement, "nil") if removable_here
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
          COMPARISON.fetch(node.name, []).each do |replacement|
            case replacement
            when Swap then add("comparison", node.message_loc, replacement.operator)
            when Literal then add("comparison", node, replacement.text)
            end
          end
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

      # An operand of && / and binds at least as tightly as the expression it
      # replaces, so it needs no parentheses (the re-parse check backs this).
      def mutate_boolean(node)
        [node.left, node.right].each { |operand| add("boolean_logic", node, operand.slice) }
        add("boolean_logic", node, ABSORBING.fetch(node.operator_loc.slice))
      end

      # Replacing a loop condition with the value that never ends it would
      # only produce timeouts, so that one is skipped.
      def mutate_condition(predicate, hang_on:)
        (%w[true false] - [hang_on]).each { |literal| add("condition_#{literal}", predicate, literal) }
      end

      def mutate_number(node)
        value = node.value
        candidates = [value + 1, value - 1, 0]
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
        !node.public_send(name).nil?
      end

      def arid?(node)
        source = node.slice
        @arid.any? { |pattern| pattern.match?(source) }
      end

      # node_or_location: a Prism node or location (both have offsets and slice).
      def add(operator, node_or_location, replacement, coarse: false)
        location = node_or_location
        return if location.slice == replacement

        edit = Edit.new(file: @subject.file, start_byte: location.start_offset,
                        end_byte: location.end_offset, replacement: replacement)
        @found << Mutation.new(subject_id: @subject.id, operator: operator, edits: [edit],
                               coarse: coarse, source: name)
      end
    end
  end
end
