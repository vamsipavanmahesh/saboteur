# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Weakens a regex literal: drops one anchor (\A, \z, \Z, ^, $) at a time
    # and swaps each + or * quantifier for the other (#135). Escaped
    # characters, character classes, and lazy or possessive stacks stay
    # untouched, and interpolated regexes stay out: their bytes are not a
    # stable 1:1 map. Anchors make validations decisive, so a dropped anchor
    # or a widened quantifier is exactly the mutant a weak test misses.
    class RegexReplacement < Base
      include OperatorVisit

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "regex_replacement"
      end

      BACKSLASH = 0x5C
      ANCHOR_ESCAPES = %w[\\A \\z \\Z].freeze

      private

      def mutate_node(node, subject, found)
        return unless node.is_a?(Prism::RegularExpressionNode)

        base = node.content_loc.start_offset
        scan_anchors_and_quantifiers(node.content) do |offset, length, replacement|
          edit = Edit.new(file: subject.file, start_byte: base + offset, end_byte: base + offset + length,
                          replacement: replacement)
          found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
        end
      end

      # Yields [offset, length, replacement] for each anchor drop and
      # quantifier swap, scanning bytes so offsets line up with the file.
      def scan_anchors_and_quantifiers(pattern)
        bytes = pattern.bytes
        depth = 0
        index = 0
        while index < bytes.size
          if bytes[index] == BACKSLASH
            yield index, 2, "" if depth.zero? && ANCHOR_ESCAPES.include?(pattern.byteslice(index, 2))
            index += 2
          else
            depth = scan_plain_byte(bytes, index, depth) { |offset, replacement| yield offset, 1, replacement }
            index += 1
          end
        end
      end

      # One non-escape byte; returns the character-class depth after it.
      def scan_plain_byte(bytes, index, depth)
        case bytes[index]
        # [ opens a class only at top level or as a POSIX [:class:];
        # inside a class it is a literal member.
        when 0x5B then depth.zero? || bytes[index + 1] == 0x3A ? depth + 1 : depth
        when 0x5D then depth.positive? ? depth - 1 : 0 # ]
        when 0x5E, 0x24 # ^ $
          yield index, "" if depth.zero?
          depth
        when 0x2B, 0x2A # + *
          yield index, (bytes[index] == 0x2B ? "*" : "+") if depth.zero? && plain_quantifier?(bytes, index)
          depth
        else
          depth
        end
      end

      # A bare quantifier: not the start of the pattern, not after an open
      # group or alternation, and not stacked into a lazy (+?, ??) or
      # possessive (*+, ++) form on either side.
      def plain_quantifier?(bytes, index)
        return false if index.zero?

        previous = bytes[index - 1]
        return false if [0x28, 0x7C, 0x3F, 0x2B, 0x2A].include?(previous) # ( | ? + *

        nxt = bytes[index + 1]
        nxt != 0x2B && nxt != 0x2A && nxt != 0x3F # + * ?
      end
    end
  end
end
