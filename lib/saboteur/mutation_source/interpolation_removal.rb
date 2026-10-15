# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "base"

module Saboteur
  module MutationSource
    # Removes one piece of an interpolated string at a time: each #{expr}
    # and each literal segment. Plain strings stay with literal_replacement
    # and backticks stay untouched (the hazard guard owns those).
    class InterpolationRemoval < Base
      SCOPE_NODES = [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

      # Base inherits Object's empty initializer; there is no parent state to set.
      def initialize(arid: []) # rubocop:disable Lint/MissingSuper
        @arid = arid.map { |pattern| Regexp.new(pattern) }
      end

      def name
        "interpolation_removal"
      end

      def mutations_for(subject)
        found = []
        visit(subject.node.body, subject, found)
        found
      end

      private

      def visit(node, subject, found)
        return if node.nil? || SCOPE_NODES.any? { |scope| node.is_a?(scope) }

        if node.is_a?(Prism::StatementsNode)
          node.body.each { |statement| visit(statement, subject, found) unless arid?(statement) }
          return
        end

        remove_parts(node, subject, found) if node.is_a?(Prism::InterpolatedStringNode)
        node.compact_child_nodes.each { |child| visit(child, subject, found) }
      end

      def remove_parts(node, subject, found)
        node.parts.each do |part|
          location = part.location
          edit = Edit.new(file: subject.file, start_byte: location.start_offset,
                          end_byte: location.end_offset, replacement: "")
          found << Mutation.new(subject_id: subject.id, operator: name, edits: [edit], source: name)
        end
      end

      def arid?(node)
        @arid.any? { |pattern| pattern.match?(node.slice) }
      end
    end
  end
end
