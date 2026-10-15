# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"
require_relative "operator_visit"

module Saboteur
  module MutationSource
    # Removes one piece of an interpolated string at a time: each #{expr}
    # and each literal segment. Plain strings stay with literal_replacement
    # and backticks stay untouched (the hazard guard owns those).
    class InterpolationRemoval < Base
      include OperatorVisit

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "interpolation_removal"
      end

      private

      def mutate_node(node, subject, found)
        remove_parts(node, subject, found) if node.is_a?(Prism::InterpolatedStringNode)
      end

      def remove_parts(node, subject, found)
        node.parts.each do |part|
          location = part.location
          edit = Edit.new(file: subject.file, start_byte: location.start_offset,
                          end_byte: location.end_offset, replacement: "")
          found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
        end
      end
    end
  end
end
