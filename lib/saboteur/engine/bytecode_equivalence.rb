# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # Trivial compiler equivalence: a mutant whose method compiles to the
    # same instruction sequence as the original cannot change behaviour, so
    # running it can only produce a false survivor. Line numbers, positions
    # and object addresses are stripped before comparing.
    class BytecodeEquivalence
      NOISE = [
        /\(\s*\d+\)(\[\w+\])?/,          # per-instruction line marker
        /\(\d+,\d+\)-\(\d+,\d+\)/,       # iseq source span
        /@<compiled>:\d+/,               # iseq first line
        /0x\h+/                          # object addresses
      ].freeze

      # True when mutated_text compiles to the same instructions as the
      # original subject source. Anything the compiler cannot judge counts
      # as not equivalent, so the mutant still runs.
      def equivalent?(original_text, mutated_text)
        original = fingerprint_of_original(original_text)
        return false unless original

        original == fingerprint(mutated_text)
      end

      private

      # Mutants of one method arrive together, so the last original is enough.
      def fingerprint_of_original(text)
        return @original_fingerprint if text == @original_text

        @original_text = text
        @original_fingerprint = fingerprint(text)
      end

      def fingerprint(text)
        listing = RubyVM::InstructionSequence.compile(text).disasm
        NOISE.reduce(listing) { |memo, pattern| memo.gsub(pattern, "") }.gsub(/^==.*\n/, "")
      rescue SyntaxError, StandardError
        nil
      end
    end
  end
end
