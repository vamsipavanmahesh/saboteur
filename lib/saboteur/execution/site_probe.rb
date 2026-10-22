# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"

module Saboteur
  module Execution
    # Records, in the mutant's child, whether the mutated expression produced
    # a different value from the original one (#1290). The mutated site is
    # wrapped as (observe((mutated), [operands]) { original }). The mutated
    # expression runs exactly once and first, as it does unwrapped, so the
    # suite sees the same calls and the same verdict. The original runs
    # only when every operand is a core immutable (Integer, Float, Rational,
    # Symbol, nil, true, false, a frozen String), so only built-in operators
    # execute; with any other operand the site is not probed and reports
    # nil. Only side-effect-free site shapes are wrapped at all (literals,
    # local and instance variable reads, arithmetic and comparison on
    # those).
    module SiteProbe
      OPERATORS = %i[+ - * / % ** < <= > >= == != <=> & | ^ ! -@ +@ ~].freeze
      LEAVES = [Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::SymbolNode, Prism::NilNode,
                Prism::TrueNode, Prism::FalseNode, Prism::LocalVariableReadNode,
                Prism::InstanceVariableReadNode].freeze

      @hits = 0
      @differed = false
      @comparable = true

      class << self
        # The def text with the mutated site wrapped, or nil when the site
        # cannot be probed safely. mutated_text is what the run would
        # evaluate unwrapped; the wrap is only offered when it is exactly
        # the source with the mutation's edits applied.
        def text(subject, mutation, mutated_text)
          return nil unless subject.respond_to?(:whole_file_only?) && mutation.respond_to?(:edits)
          return nil if subject.whole_file_only? || mutation.edits.size != 1

          source = subject.source
          return nil unless subject.apply(mutation.edits) == mutated_text

          edit = mutation.edits.first
          range = (edit.start_byte - subject.start_byte)...(edit.end_byte - subject.start_byte)
          wrap(source.b, range, edit.replacement.b)&.force_encoding(Encoding::UTF_8)
        rescue StandardError
          nil # a probe must never turn a mutant run into an error
        end

        def reset
          @hits = 0
          @differed = false
          @comparable = true
        end

        # nil: the site never ran, or its values could not be compared.
        def differed
          return nil if @hits.zero? || !@comparable

          @differed
        end

        def observe(mutated, operands, &)
          compare(mutated, &) if operands.all? { |operand| immutable?(operand) }
          mutated
        end

        private

        def immutable?(value)
          case value
          when Integer, Float, Rational, Symbol, nil, true, false then true
          when String then value.frozen?
          else false
          end
        end

        def compare(mutated)
          original = yield
          @hits += 1
          @differed ||= original != mutated
        rescue StandardError
          @comparable = false
        end

        def wrap(source, range, replacement)
          top = site(Prism.parse(source).value, range)
          # A bare edited literal differs from itself by construction: no signal.
          return nil if top.nil? || LEAVES.any? { |leaf| top.is_a?(leaf) }

          from = top.location.start_offset
          to = top.location.end_offset
          original = source.byteslice(from...to)
          mutated = original.byteslice(0, range.begin - from) + replacement + original.byteslice((range.end - from)..)
          return nil if (original + mutated).include?("\n")

          source.byteslice(0, from) + probe(top, original, mutated) + source.byteslice(to..)
        end

        def probe(top, original, mutated)
          reads = []
          collect_reads(top, reads)
          operands = reads.uniq.join(", ")
          "(::Saboteur::Execution::SiteProbe.observe((#{mutated}), [#{operands}]) { #{original} })".b
        end

        def collect_reads(node, reads)
          reads << node.slice if node.is_a?(Prism::LocalVariableReadNode) || node.is_a?(Prism::InstanceVariableReadNode)
          node.compact_child_nodes.each { |child| collect_reads(child, reads) }
        end

        # The outermost pure expression around the edit, climbing while the
        # parent is pure too.
        def site(root, range)
          path = path_to(root, range).grep_v(Prism::ArgumentsNode)
          index = path.rindex { |node| pure?(node) }
          return nil unless index

          index -= 1 while index.positive? && climbable?(path[index - 1])
          path[index]
        end

        def climbable?(node)
          (node.is_a?(Prism::CallNode) || node.is_a?(Prism::ParenthesesNode)) && pure?(node)
        end

        def path_to(node, range)
          path = [node]
          loop do
            child = node.compact_child_nodes.find do |c|
              c.location.start_offset <= range.begin && range.end <= c.location.end_offset
            end
            return path unless child

            path << child
            node = child
          end
        end

        def pure?(node)
          case node
          when *LEAVES then true
          when Prism::ParenthesesNode then pure_parentheses?(node)
          when Prism::CallNode then pure_call?(node)
          else false
          end
        end

        def pure_parentheses?(node)
          body = node.body
          body.is_a?(Prism::StatementsNode) && body.body.size == 1 && pure?(body.body.first)
        end

        def pure_call?(node)
          return false unless OPERATORS.include?(node.name) && node.block.nil? && node.receiver

          pure?(node.receiver) && Array(node.arguments&.arguments).size <= 1 &&
            Array(node.arguments&.arguments).all? { |arg| pure?(arg) }
        end
      end
    end
  end
end
