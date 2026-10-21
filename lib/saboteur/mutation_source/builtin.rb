# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "filter_replacement"
require_relative "copy_replacement"
require_relative "literal_replacement"
require_relative "argument_removal"
require_relative "argument_swap"
require_relative "chain_removal"
require_relative "pair_removal"
require_relative "element_removal"
require_relative "endpoint_replacement"
require_relative "operator_registry"
require_relative "range_replacement"
require_relative "operator_assignment"
require_relative "condition_negation"
require_relative "method_swap"
require_relative "operand_replacement"
require_relative "interpolation_removal"
require_relative "jump_value"
require_relative "regex_replacement"
require_relative "rescue_removal"
require_relative "ensure_removal"
require_relative "when_removal"
require_relative "unary_removal"
require_relative "unary_insertion"
require_relative "break_next_swap"

module Saboteur
  module MutationSource
    # The v1 operator set. Every mutation is a byte-range edit of the original
    # file text; nothing is unparsed.
    class Builtin < Base
      DEFAULT_ARID = [
        '\A(puts|pp|p|print|warn)\b',
        # Exception message arguments read as diagnostics too (#1066): a
        # raise/fail string edit sits inside the call, so the line and the
        # call head both have to match.
        '\A(raise|fail)\b',
        '\A(@|self\.|::)?(Rails\.)?logger\b',
        # A logger at the end of a receiver chain: Sentry.sdk_logger.warn
        # (#665). The match is case-sensitive, so SDK_LOGGER stays
        # ordinary. The segment must END in logger, so
        # @loggers.each and catalogger.warnings still mutate.
        '\A(\w+\.)*\w*logger\.(debug|info|warn|error|fatal)\b',
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
                  Prism::CallOrWriteNode, Prism::IndexOrWriteNode].freeze
      AND_WRITE = [Prism::LocalVariableAndWriteNode, Prism::InstanceVariableAndWriteNode,
                   Prism::ClassVariableAndWriteNode, Prism::GlobalVariableAndWriteNode,
                   Prism::CallAndWriteNode, Prism::IndexAndWriteNode].freeze
      # Inside a def, X = a is a syntax error (dynamic constant assignment), so
      # constant targets only get the mutant for a define_method body, which is a block.
      CONSTANT_WRITE = { Prism::ConstantOrWriteNode => "or_assign", Prism::ConstantPathOrWriteNode => "or_assign",
                         Prism::ConstantAndWriteNode => "and_assign",
                         Prism::ConstantPathAndWriteNode => "and_assign" }.freeze
      CATCH_ALL = %w[StandardError ::StandardError Exception ::Exception].freeze
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze
      # The single-purpose sources, in the order they run after the shared walk.
      DELEGATED = [
        FilterReplacement, CopyReplacement, LiteralReplacement, ArgumentRemoval, PairRemoval, ElementRemoval,
        ChainRemoval, EndpointReplacement, RangeReplacement, OperatorAssignment, ConditionNegation, MethodSwap,
        OperandReplacement, InterpolationRemoval, RegexReplacement, ArgumentSwap, JumpValue, RescueRemoval,
        EnsureRemoval, WhenRemoval, UnaryRemoval, UnaryInsertion, BreakNextSwap
      ].freeze

      def initialize(arid: DEFAULT_ARID, operators: [], exclude_operators: [])
        super()
        @operators = OperatorRegistry.select(operators, exclude_operators)
        @arid = arid.map { |pattern| pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern) }
        @delegated = DELEGATED.map { |source| source.new(arid: arid) }
      end

      def name
        "builtin"
      end

      def mutations_for(subject)
        body = subject.body_node
        @subject = subject
        @found = []
        coarse(body)
        visit(body)
        @found.concat(delegated.flat_map { |source| source.mutations_for(subject) })
        @found.select { |mutation| @operators.include?(mutation.operator) }
      ensure
        @subject = nil
      end

      # The single-purpose sources run after the shared walk, in registration
      # order; each filters its own operator through the same policy below.
      attr_reader :delegated

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
        statements.body.all? { |statement| arid_statement?(statement) }
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
          next if arid_statement?(statement)

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
        when *AND_WRITE then add("and_assign", node.operator_loc, "=")
        when *CONSTANT_WRITE.keys then mutate_constant_write(node)
        end
      end

      def mutate_constant_write(node)
        add(CONSTANT_WRITE.fetch(node.class), node.operator_loc, "=") if @subject.node.is_a?(Prism::CallNode)
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

      # Only the infix spelling is binary: an operator call has no call
      # operator, and its receiver, message, single argument and lack of a
      # block all follow from that (a block binds to the last operand's own
      # call, never to the operator).
      def binary?(node)
        node.call_operator_loc.nil?
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

      # An arid call is noise only in itself. A block on that call is real
      # work (a notifier wrapping a computation), so the statement still
      # mutates and keeps its body out of nothing_to_remove?; the walk
      # descends into the block through the normal visit below.
      def arid_statement?(statement)
        return false unless arid?(statement)

        block = statement.is_a?(Prism::CallNode) ? statement.block : nil
        body = block.is_a?(Prism::BlockNode) ? block.body : nil
        # A do-block with rescue/ensure parses its body as a BeginNode, not
        # a StatementsNode (#464): its clauses are real work, not noise.
        return false if body && !body.is_a?(Prism::StatementsNode)

        body.nil? || body.body.all? { |inner| arid_statement?(inner) }
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
