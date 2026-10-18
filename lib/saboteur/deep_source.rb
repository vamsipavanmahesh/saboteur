# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # A file nested deeper than the walkers can safely recurse (#719).
  class DeepSourceError < Error
    def initialize(file, limit)
      super("#{file} nests deeper than #{limit} AST levels; saboteur cannot walk it safely")
    end
  end

  # The AST walkers (SubjectFinder, ConstantSubjectFinder, AttributeFinder
  # and the operator visits) recurse one stack frame per nesting level and
  # overflow the Ruby stack around a thousand nested calls, while Prism
  # still parses to about five thousand (#719). Measuring depth iteratively
  # before any walk turns that crash into a clean refusal: the CLI boundary
  # prints one line naming the file and exits 3.
  module DeepSource
    # Two AST levels per nested call (`a(` adds a CallNode and an
    # ArgumentsNode). The finders walk a file from its root and survive a
    # thousand nested calls, so their limit sits just above that. The
    # operator visits recurse deeper per level (method_swap overflows a
    # bare stack around 900 nested calls, earlier under the engine), so a
    # subject's body refuses earlier. Both margins stay deterministic:
    # a clean refusal instead of a SystemStackError that depends on how
    # deep the caller's stack already is.
    MAX_AST_DEPTH = 2200
    MAX_MUTATION_DEPTH = 1200

    def self.check!(program, file, limit: MAX_AST_DEPTH)
      raise DeepSourceError.new(file, limit) if depth(program) > limit
    end

    # Iterative on purpose: a recursive measure would crash on exactly the
    # files it exists to catch (#719, same shape as #711).
    def self.depth(node)
      max = 0
      work = [[node, 1]]
      until work.empty?
        current, level = work.pop
        next if current.nil?

        max = level if level > max
        current.compact_child_nodes.each { |child| work << [child, level + 1] }
      end
      max
    end
  end
end
