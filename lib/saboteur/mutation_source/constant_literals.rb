# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "pair_removal"
require_relative "element_removal"
require_relative "operator_registry"

module Saboteur
  module MutationSource
    # Mutations for a constant hash or array literal (a ConstantSubject,
    # issue #306): pair_removal on the hash's entries, element_removal on
    # the array's elements. The other operators stay method-only. Every
    # entry is proposed here; in --since mode the diff scope narrows the
    # proposals to the changed entries, and a configured operator exclusion
    # applies as usual.
    class ConstantLiterals < Base
      def initialize(operators: [], exclude_operators: [], arid: [])
        super()
        @operators = OperatorRegistry.select(operators, exclude_operators)
        @pair_removal = PairRemoval.new(arid: arid)
        @element_removal = ElementRemoval.new
      end

      def name
        "builtin"
      end

      def mutations_for(subject)
        literal = subject.literal_node
        found = []
        if literal.is_a?(Prism::HashNode) && @operators.include?("pair_removal")
          found.concat(@pair_removal.mutations_for(subject, root: literal))
        end
        if literal.is_a?(Prism::ArrayNode) && @operators.include?("element_removal")
          found.concat(@element_removal.mutations_for(subject, root: literal))
        end
        found
      end
    end
  end
end
