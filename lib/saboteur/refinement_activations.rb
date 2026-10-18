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

    # Iterative on purpose: recursion here crashed whole runs with a raw
    # SystemStackError on deeply nested source (#711). Sibling children
    # push in reverse so they record in the recursion's order; a ClassNode
    # visits its body before its superclass here, unlike the recursion,
    # which changes nothing - the site list only feeds any? checks.
    def self.collect(node, scope_end, dynamic, sites)
      work = [[node, scope_end, dynamic]]
      visit(*work.pop, work, sites) until work.empty?
    end

    def self.visit(current, scope_end, dynamic, work, sites)
      if current.is_a?(Prism::CallNode) && current.name == :using && current.receiver.nil?
        sites << Site.new(start_byte: current.start_offset, scope_end: scope_end, dynamic_scope: dynamic)
      end

      children_of(current, scope_end, dynamic).reverse_each { |entry| work << entry }
    end

    def self.children_of(current, scope_end, dynamic)
      case current
      when Prism::ClassNode
        entries = []
        entries << [current.body, current.end_offset, dynamic] if current.body
        entries << [current.superclass, scope_end, dynamic] if current.superclass
        entries
      when Prism::ModuleNode, Prism::SingletonClassNode
        current.body ? [[current.body, current.end_offset, dynamic]] : []
      when Prism::DefNode, Prism::BlockNode, Prism::LambdaNode
        current.compact_child_nodes.map { |child| [child, scope_end, true] }
      else
        current.compact_child_nodes.map { |child| [child, scope_end, dynamic] }
      end
    end
  end
end
