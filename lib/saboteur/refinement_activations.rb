# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # The lexical `using` sites of one parsed file (#634). A bare `using`
  # activates its refinement from where it sits to the end of its own
  # scope: a class or module body, or the whole file at the top level.
  # Activation is lexical, not namespaced: a `class ::Q` nested inside
  # the body still sees it, while a reopened body with the same constant
  # path after the scope's `end` does not. Sites therefore compare byte
  # ranges, not constant paths: a site covers a subject that starts after
  # the `using` and before the scope's closing `end`. A `using` inside a
  # method or block body cannot be scoped this way, so one anywhere keeps
  # the old whole-file skip. Skipping only ever means "not mutated",
  # never a wrong verdict.
  class RefinementActivations
    Site = Data.define(:start_byte, :scope_end, :dynamic_scope) do
      def covers?(subject)
        !dynamic_scope && subject.start_byte > start_byte && subject.start_byte < scope_end
      end
    end

    def self.mark(subjects, program)
      sites = []
      collect(program, program.end_offset, false, sites)
      return if sites.empty?

      if sites.any?(&:dynamic_scope)
        subjects.each { |subject| subject.skip_reason = "refinements" }
        return
      end

      subjects.each do |subject|
        subject.skip_reason = "refinements" if sites.any? { |site| site.covers?(subject) }
      end
    end

    def self.collect(node, scope_end, dynamic, sites)
      if node.is_a?(Prism::CallNode) && node.name == :using && node.receiver.nil?
        sites << Site.new(start_byte: node.location.start_offset, scope_end: scope_end, dynamic_scope: dynamic)
      end

      descend(node, scope_end, dynamic, sites)
    end

    def self.descend(node, scope_end, dynamic, sites)
      case node
      when Prism::ClassNode
        collect(node.superclass, scope_end, dynamic, sites) if node.superclass
        collect(node.body, node.end_offset, dynamic, sites) if node.body
      when Prism::ModuleNode, Prism::SingletonClassNode
        collect(node.body, node.end_offset, dynamic, sites) if node.body
      when Prism::DefNode, Prism::BlockNode, Prism::LambdaNode
        node.compact_child_nodes.each { |child| collect(child, scope_end, true, sites) }
      else
        node.compact_child_nodes.each { |child| collect(child, scope_end, dynamic, sites) }
      end
    end
  end
end
