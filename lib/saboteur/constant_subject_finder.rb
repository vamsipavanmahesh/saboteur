# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "subject"
require_relative "constant_subject"

module Saboteur
  # Finds constant assignments of hash and array literals - `RULES = { ... }`,
  # `TAGS = [ ... ]`, with a trailing `.freeze` or a similar argument-free,
  # block-free call - as mutation subjects for --since runs (issue #306).
  #
  # Unsupported forms are reported with a reason, never silently skipped: a
  # namespaced target (`A::RULES = ...`), a conditional write
  # (`RULES ||= ...`), and a non-literal value (a method call with
  # arguments, another constant). Class factories (`Point = Data.define(...)`)
  # are scopes, not data: they are reported neither way, and a constant
  # inside the factory's block belongs to the new class. Constants inside a
  # block are found but marked skipped, like SubjectFinder's defs, so the
  # report names them.
  class ConstantSubjectFinder
    Parsed = Data.define(:subjects, :unsupported, :errors)

    # A constant assignment saboteur cannot mutate, with the reason why.
    Unsupported = Data.define(:name, :owner, :file, :node, :reason) do
      def id
        owner ? "#{owner}::#{name}" : name.to_s
      end

      def overlaps_lines?(lines)
        first = node.location.start_line
        last = node.location.end_line
        if lines.is_a?(Range)
          lines.begin <= last && first <= lines.end
        else
          lines.any? { |line| line.between?(first, last) }
        end
      end
    end

    CLASS_FACTORIES = SubjectFinder::CLASS_FACTORIES

    # source: the text to parse when it is not the file on disk (the file as
    # it was at an earlier commit).
    def call(file, source: File.binread(file))
      result = Prism.parse(source)
      return Parsed.new(subjects: [], unsupported: [], errors: result.errors.map(&:message)) if result.failure?

      ctx = { file: file, source: source, frozen: frozen_literals?(result) }
      out = { subjects: [], unsupported: [] }
      walk(result.value, [], out, **ctx)
      reject_duplicates(out, **ctx)
      Parsed.new(subjects: out[:subjects], unsupported: out[:unsupported], errors: [])
    end

    private

    # More than one write of the same constant in one file: re-evaluating
    # the file runs them all, the later one always wins, and a mutant of
    # any earlier literal is never observed. EVERY write counts - a guarded
    # or non-literal second write (`RULES = {a: 1}; RULES = build_rules`)
    # overwrites the first just the same (#319).
    def reject_duplicates(out, **ctx)
      writes = Hash.new(0)
      (out[:subjects] + out[:unsupported]).each { |entry| writes[entry.id] += 1 }
      duplicates = out[:subjects].select { |subject| writes[subject.id] > 1 }
      return if duplicates.empty?

      out[:subjects] -= duplicates
      duplicates.each do |subject|
        out[:unsupported] << Unsupported.new(name: subject.name, owner: subject.owner, file: ctx[:file],
                                             node: subject.node,
                                             reason: "assigned more than once in this file")
      end
    end

    def frozen_literals?(result)
      result.magic_comments.any? do |comment|
        comment.key.tr("-", "_").casecmp?("frozen_string_literal") && comment.value.casecmp?("true")
      end
    end

    def walk(node, nesting, out, **ctx)
      return if node.nil?

      case node
      when Prism::BlockNode, Prism::LambdaNode
        walk(node.body, nesting, out, **ctx, in_block: true)
      when Prism::ConstantWriteNode
        constant_assignment(node, nesting, out, **ctx)
      when Prism::IfNode, Prism::UnlessNode
        walk_conditional(node, nesting, out, **ctx)
      when Prism::ConstantOrWriteNode, Prism::ConstantAndWriteNode
        record_unsupported(out, node, nesting, "a conditional assignment (#{node.operator_loc.slice})", **ctx)
        walk_children(node, nesting, out, **ctx)
      when Prism::ConstantPathWriteNode, Prism::ConstantPathOrWriteNode, Prism::ConstantPathAndWriteNode
        record_unsupported(out, node, nesting, "a namespaced target (#{node.target.slice})", **ctx)
        walk_children(node, nesting, out, **ctx)
      when Prism::ModuleNode
        walk(node.body, nesting + [Scope.new(kind: :module, path: node.constant_path.slice)], out, **ctx)
      when Prism::ClassNode
        walk(node.body, nesting + [Scope.new(kind: :class, path: node.constant_path.slice)], out, **ctx)
      else
        # A singleton class keeps the enclosing nesting: constant lookup
        # reaches the attached class's constants from there.
        walk_children(node, nesting, out, **ctx)
      end
    end

    # A write under a condition may never run: mutating its literal cannot
    # change the constant when the guard skips the write (#319).
    def walk_conditional(node, nesting, out, **ctx)
      walk(node.predicate, nesting, out, **ctx)
      walk(node.statements, nesting, out, **ctx, guarded: true)
      walk(node.respond_to?(:subsequent) ? node.subsequent : node.else_clause, nesting, out, **ctx,
           guarded: true)
    end

    def walk_children(node, nesting, out, **ctx)
      node.compact_child_nodes.each { |child| walk(child, nesting, out, **ctx) }
    end

    def constant_assignment(node, nesting, out, **ctx)
      return walk_factory(node, nesting, out, **ctx) if factory_scope?(node)

      literal = literal_value(node.value)
      reason = unsupported_reason(node, literal, **ctx)
      if reason
        record_unsupported(out, node, nesting, reason, **ctx)
        walk_children(node, nesting, out, **ctx)
        return
      end

      subject = ConstantSubject.new(name: node.name, owner: owner_path(nesting), file: ctx[:file], node: node,
                                    literal_node: literal, file_source: ctx[:source], nesting: nesting,
                                    frozen_literals: ctx[:frozen])
      subject.skip_reason = "defined inside a block" if ctx[:in_block]
      out[:subjects] << subject
      # Another constant can hide in the literal's values (`MAP = { x: (Y = []) }`).
      walk_children(node, nesting, out, **ctx)
    end

    # `Point = Data.define(:x) do ... end`: the block's constants belong
    # to Point; the receiver and arguments stay in the enclosing scope.
    def walk_factory(node, nesting, out, **ctx)
      call = node.value
      (call.compact_child_nodes - [call.block]).each { |child| walk(child, nesting, out, **ctx) }
      walk(call.block, nesting + [Scope.new(kind: :class, path: node.name.to_s)], out, **ctx)
    end

    def unsupported_reason(_node, literal, guarded: false, **)
      return "guarded by a condition" if guarded
      return "its value is not a hash or array literal" if literal.nil?

      nil
    end

    # `Point = Data.define(...) do ... end`: only the four core factories
    # count, called on the bare constant (mirrors SubjectFinder).
    def factory_scope?(node)
      call = node.value
      return false unless call.is_a?(Prism::CallNode) && call.block.is_a?(Prism::BlockNode)
      return false unless call.receiver.is_a?(Prism::ConstantReadNode)

      CLASS_FACTORIES[call.receiver.name] == call.name
    end

    # The hash or array literal behind the value, looking through `.freeze`
    # calls only: any other receiver chain transforms the value, so the
    # literal is not what the constant holds.
    def literal_value(value)
      value = value.receiver while value.is_a?(Prism::CallNode) && value.name == :freeze &&
                                   value.arguments.nil? && value.block.nil? && value.receiver
      value if value.is_a?(Prism::HashNode) || value.is_a?(Prism::ArrayNode)
    end

    def record_unsupported(out, node, nesting, reason, **ctx)
      name = node.respond_to?(:name) ? node.name : node.target.slice
      out[:unsupported] << Unsupported.new(name: name, owner: owner_path(nesting), file: ctx[:file],
                                           node: node, reason: reason)
    end

    # Lexical path of the enclosing class/module, or nil at the top level.
    def owner_path(nesting)
      parts = nesting.map(&:path)
      return nil if parts.empty?

      parts.each_with_object([]) do |path, acc|
        acc.clear if path.start_with?("::")
        acc << path.delete_prefix("::")
      end.join("::")
    end
  end
end
