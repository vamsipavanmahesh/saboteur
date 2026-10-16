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
      result = Prism.parse(source, filepath: file)
      return Parsed.new(subjects: [], unsupported: [], errors: result.errors.map(&:message)) if result.failure?

      ctx = { file: file, source: source, frozen: frozen_literals?(result), in_block: false }
      out = { subjects: [], unsupported: [] }
      walk(result.value, [], out, **ctx)
      Parsed.new(subjects: out[:subjects], unsupported: out[:unsupported], errors: [])
    end

    private

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

    def walk_children(node, nesting, out, **ctx)
      node.compact_child_nodes.each { |child| walk(child, nesting, out, **ctx) }
    end

    def constant_assignment(node, nesting, out, **ctx)
      if factory_scope?(node)
        # `Point = Data.define(:x) do ... end`: the block's constants belong
        # to Point; the receiver and arguments stay in the enclosing scope.
        call = node.value
        (call.compact_child_nodes - [call.block]).each { |child| walk(child, nesting, out, **ctx) }
        walk(call.block, nesting + [Scope.new(kind: :class, path: node.name.to_s)], out, **ctx)
        return
      end

      literal = literal_value(node.value)
      unless literal
        record_unsupported(out, node, nesting, "its value is not a hash or array literal", **ctx)
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

    # `Point = Data.define(...) do ... end`: only the four core factories
    # count, called on the bare constant (mirrors SubjectFinder).
    def factory_scope?(node)
      call = node.value
      return false unless call.is_a?(Prism::CallNode) && call.block.is_a?(Prism::BlockNode)
      return false unless call.receiver.is_a?(Prism::ConstantReadNode)

      CLASS_FACTORIES[call.receiver.name] == call.name
    end

    # The hash or array literal behind the value, looking through
    # argument-free, block-free calls such as `.freeze`.
    def literal_value(value)
      value = value.receiver while value.is_a?(Prism::CallNode) && value.arguments.nil? &&
                                   value.block.nil? && value.receiver
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
