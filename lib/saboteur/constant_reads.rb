# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "text"

module Saboteur
  # The lines where a constant is read, per file: the tests covering those
  # lines are the ones that can observe a change to the constant's value
  # (issue #306).
  #
  # Matching is lexical and honest about its edges. A bare `RULES` matches
  # when its scope is the constant's owner or nested under it (constant
  # lookup climbs lexical scopes) or the constant is top-level; a
  # `Shop::RULES` path matches by its full spelling. A scope that writes its
  # own `RULES` shadows the outer constant: reads under it resolve to the
  # inner one and do not count. Reads reached through a superclass,
  # `const_get`, or a compact `class Shop::Item` scope are not resolved: a
  # constant only read that way finds no consumer here, and the run reports
  # it as ran-at-load instead of guessing.
  #
  # Runtime reads (inside a def body) observe the constant when the mutant
  # runs; load-time reads outside the constant's own file do not: the other
  # file was loaded once with the original value and re-evaluating the
  # constant's file does not run it again, so a read like
  # `COPY = A::RULES` there keeps the original (#319). A capture inside a
  # boot-time block (`1.times { COPY = A::RULES }`) is treated the same:
  # statement-level blocks run while the file loads. That is a heuristic -
  # a block passed to a deferring call (at_exit, define_method) runs later,
  # but treating it as load-time errs toward dropping a constant rather
  # than reporting a mutant nobody can observe.
  module ConstantReads
    Reads = Data.define(:runtime, :load, :defs)

    module_function

    # { "/abs/file.rb" => Reads } for the files that read the constant.
    # runtime: def-body and block lines - a block runs when its caller runs
    # it (an `it` block during the example), and line coverage decides
    # whether any test reached it. load: top-level or class-body statement
    # lines (observable only in the constant's own file, which the mutant
    # re-evaluates). defs: the start line of each def a runtime read sits
    # in, for the method-call counter fallback (endless defs have no line
    # coverage). Only files whose text mentions the name are parsed.
    def across(files, constant)
      mention = /\b#{Regexp.escape(constant.name.to_s)}\b/
      files.each_with_object({}) do |file, hits|
        source = File.binread(file)
        next unless mentions?(source, mention)

        reads = reads_in(source, constant)
        hits[file] = reads unless reads.runtime.empty? && reads.load.empty?
      end
    end

    # The lines a mutant of the constant can be observed through: runtime
    # reads everywhere, load reads in the constant's own file only.
    def observable_lines(reads_by_file, constant)
      reads_by_file.each_with_object({}) do |(file, reads), hits|
        lines = reads.runtime.dup
        lines.concat(reads.load) if file == constant.file
        hits[file] = lines.uniq.sort unless lines.empty?
      end
    end

    def mentions?(source, mention)
      Text.utf8_identity(source).match?(mention)
    rescue Encoding::CompatibilityError, ArgumentError
      false
    end

    def reads_in(source, constant)
      result = Prism.parse(source)
      return Reads.new([], [], []) if result.failure?

      out = { runtime: [], load: [], defs: [] }
      walk(result.value, [], constant, out, in_def: nil, in_block: false, shadowed: nil)
      Reads.new(out[:runtime].uniq.sort, out[:load].uniq.sort, out[:defs].uniq.sort)
    end

    def walk(node, nesting, constant, out, in_def:, in_block:, shadowed:, capture: false)
      return if node.nil?

      case node
      when Prism::DefNode
        walk(node.body, nesting, constant, out, in_def: node.location.start_line, in_block: false,
                                                shadowed: shadowed)
      when Prism::BlockNode, Prism::LambdaNode
        walk(node.body, nesting, constant, out, in_def: in_def, in_block: true, capture: capture,
                                                shadowed: shadowed)
      when Prism::ConstantWriteNode, Prism::ConstantPathWriteNode
        # A capture (`COPY = <expr>`): the value reads the constant once,
        # when the write runs. Walk the value flagged as a capture so a
        # boot-time block write (`1.times { COPY = A::RULES }`) lands in
        # load, not runtime (#319).
        walk(node.value, nesting, constant, out, in_def: in_def, in_block: in_block, capture: true,
                                                 shadowed: shadowed)
      when Prism::ConstantReadNode
        record(node, out, in_def, in_block, capture) if !shadowed && bare_match?(node, nesting, constant)
      when Prism::ConstantPathNode
        # `Shop::RULES` holds no ConstantReadNode for RULES, only for Shop;
        # match the path's full spelling.
        record(node, out, in_def, in_block, capture) if node.slice.delete_prefix("::") == constant.id
        walk_children(node, nesting, constant, out, in_def: in_def, in_block: in_block, capture: capture,
                                                    shadowed: shadowed)
      when Prism::ModuleNode, Prism::ClassNode, Prism::SingletonClassNode
        walk_scope(node, nesting, constant, out, shadowed)
      else
        walk_children(node, nesting, constant, out, in_def: in_def, in_block: in_block, capture: capture,
                                                    shadowed: shadowed)
      end
    end

    # `class << self` joins the nesting as "<attached>.singleton_class",
    # matching how ConstantSubjectFinder names that owner (#380); a non-self
    # receiver or a top-level singleton has no static name and adds nothing.
    # The shadow carries the path of the scope that set it. Entering the
    # constant's owner scope lifts a shadow set outside it: the owner's
    # own definition is lexically closer there (#395). A shadow set
    # inside the owner subtree still binds below the nested scope that
    # wrote the constant.
    def walk_scope(node, nesting, constant, out, shadowed)
      inner = scope_nesting(node, nesting)
      path = inner.join("::")
      scopes = [constant.owner.to_s]
      shadowed = nil if shadowed && scopes.any? { |scope| path == scope || path.start_with?("#{scope}::") } &&
                        scopes.none? { |scope| shadowed == scope || shadowed.start_with?("#{scope}::") }
      shadowed = path if shadowed.nil? && path != scopes.first && writes_constant?(node.body, constant.name)
      walk(node.body, inner, constant, out, in_def: nil, in_block: false, shadowed: shadowed)
    end

    def scope_nesting(node, nesting)
      return nesting + [node.constant_path.slice.delete_prefix("::")] unless node.is_a?(Prism::SingletonClassNode)
      return nesting unless node.expression.is_a?(Prism::SelfNode) && nesting.any?

      nesting[0...-1] + ["#{nesting.last}.singleton_class"]
    end

    def walk_children(node, nesting, constant, out, in_def:, in_block:, capture:, shadowed:)
      node.compact_child_nodes.each do |child|
        walk(child, nesting, constant, out, in_def: in_def, in_block: in_block, capture: capture,
                                            shadowed: shadowed)
      end
    end

    def record(node, out, in_def, in_block, capture)
      line = node.location.start_line
      if in_def
        out[:runtime] << line
        out[:defs] << in_def
      elsif in_block && !capture
        out[:runtime] << line
      else
        # A bare statement read, or a capture in a boot-time block: both
        # resolved while the file loaded, with the original value.
        out[:load] << line
      end
    end

    # A bare `RULES` reads this constant when the read's scope is the
    # constant's owner (or its singleton scope, whose ancestry reaches the
    # attached class) or nested under either, or it is top-level (#380).
    def bare_match?(node, nesting, constant)
      return false unless node.name == constant.name
      return true if constant.owner.nil?

      path = nesting.join("::")
      [constant.owner, "#{constant.owner}.singleton_class"].any? do |scope|
        path == scope || path.start_with?("#{scope}::")
      end
    end

    # True when the scope body assigns the constant name at its own level
    # (not inside a nested def or scope).
    def writes_constant?(body, name)
      statements = body&.body || []
      statements.any? do |statement|
        statement.is_a?(Prism::ConstantWriteNode) && statement.name == name
      end
    end
  end
end
