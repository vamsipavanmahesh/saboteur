# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Trivial compiler equivalence: a mutant whose method compiles to the
    # same instruction sequence as the original cannot change behaviour, so
    # running it can only produce a false survivor. The comparison walks the
    # compiled instruction tree and drops only position metadata (line
    # numbers, line events, source spans, node ids, file paths). Operands,
    # including string and numeric literals, are compared exactly (2 and 2.0 differ, and so do +0.0 and -0.0).
    class BytecodeEquivalence
      ISEQ_MAGIC = "YARVInstructionSequence/SimpleDataFormat"
      POSITION_EVENT = /\ARUBY_EVENT_/

      # True when mutated_text compiles to the same instructions as the
      # original subject source under the same compile options. Anything the
      # compiler cannot judge counts as not equivalent, so the mutant still
      # runs. frozen_string_literal: whether the file carries that magic
      # comment, which changes how string literals compile.
      def equivalent?(original_text, mutated_text, frozen_string_literal: false)
        original = fingerprint_of_original(original_text, frozen_string_literal)
        return false unless original

        exact?(original, fingerprint(mutated_text, frozen_string_literal))
      end

      private

      # Mutants of one method arrive together, so the last original is enough.
      def fingerprint_of_original(text, frozen)
        key = [text, frozen]
        return @original_fingerprint if key == @original_key

        @original_key = key
        @original_fingerprint = fingerprint(text, frozen)
      end

      def fingerprint(text, frozen)
        options = { frozen_string_literal: frozen }
        strip_positions(RubyVM::InstructionSequence.compile(text, nil, nil, 1, options).to_a)
      rescue SyntaxError, StandardError
        nil
      end

      # Structural equality that never coerces: an Integer is not a Float,
      # and +0.0 is not -0.0 (1.0 / +0.0 and 1.0 / -0.0 are different
      # infinities), which eql? alone would not tell apart.
      def exact?(left, right)
        case left
        when Array then right.is_a?(Array) && left.size == right.size && left.zip(right).all? { |l, r| exact?(l, r) }
        when Hash then right.is_a?(Hash) && exact?(left.to_a, right.to_a)
        when Float then right.is_a?(Float) && [left].pack("G") == [right].pack("G")
        else left.eql?(right)
        end
      end

      def strip_positions(node)
        return node unless node.is_a?(Array)
        return node.map { |child| strip_positions(child) } unless node.first == ISEQ_MAGIC

        _magic, major, minor, format, _misc, name, _path, _real_path, _first_line, type, locals, params, catches,
          body = node
        [major, minor, format, name, type, locals, strip_positions(params), strip_positions(catches),
         strip_body(body)]
      end

      def strip_body(body)
        body.reject { |entry| position?(entry) }.map { |entry| strip_positions(entry) }
      end

      # Line numbers and line/call/return events depend only on layout.
      def position?(entry)
        case entry
        when Integer, POSITION_EVENT then true
        else false
        end
      end
    end
  end
end
