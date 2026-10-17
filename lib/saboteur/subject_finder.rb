# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "subject"

module Saboteur
  # Finds `def` methods in a Ruby file with Prism.
  #
  # Included: instance methods and `def self.x` inside a class or module,
  # defs inside `class << self`, and defs passed to a receiverless call such
  # as `private def x`. Skipped: top-level defs, defs nested in defs, and
  # `def obj.x` for obj != self. Defs in blocks (`included do`, builders)
  # are found but marked skipped ("defined inside a block"), so the report
  # names them instead of leaving them out - except the four core class
  # factories: `X = Data.define`, `Struct.new`, `Class.new` or `Module.new`
  # with a block names X as the owner, and its defs are ordinary subjects
  # that re-evaluate through X.class_eval (#290). Any other block, and a
  # `A::X = ...` target, keeps the enclosing owner or the placeholder.
  class SubjectFinder
    Parsed = Data.define(:subjects, :errors)
    ANONYMOUS_OWNER = "(anonymous block)"
    CLASS_FACTORIES = { Data: :define, Struct: :new, Class: :new, Module: :new }.freeze

    # source: the text to parse when it is not the file on disk (the file as
    # it was at an earlier commit).
    def call(file, source: File.binread(file))
      result = Prism.parse(source, filepath: file)
      return Parsed.new(subjects: [], errors: result.errors.map(&:message)) if result.failure?

      frozen = frozen_literals?(result)
      subjects = []
      walk(result.value, [], subjects, file: file, source: source, frozen: frozen)
      mark_refinements(subjects, result.value)
      Parsed.new(subjects: subjects, errors: [])
    end

    private

    def frozen_literals?(result)
      result.magic_comments.any? do |comment|
        comment.key.tr("-", "_").casecmp?("frozen_string_literal") && comment.value.casecmp?("true")
      end
    end

    def walk(node, nesting, out, previous: nil, **ctx)
      return if node.nil?

      case node
      when Prism::BlockNode, Prism::LambdaNode
        walk(node.body, nesting, out, **ctx, in_block: true)
      when Prism::ConstantWriteNode
        walk_constant_assignment(node, nesting, out, **ctx)
      when Prism::ModuleNode
        scope = Scope.new(kind: :module, path: node.constant_path.slice)
        walk(node.body, lexical_nesting(nesting) + [scope], out, **ctx)
      when Prism::ClassNode
        scope = Scope.new(kind: :class, path: node.constant_path.slice)
        walk(node.body, lexical_nesting(nesting) + [scope], out, **ctx)
      when Prism::SingletonClassNode
        walk_singleton_class(node, nesting, out, **ctx)
      when Prism::StatementsNode
        walk_statements(node, nesting, out, **ctx)
      when Prism::DefNode
        add_subject(node, nesting, out, previous: previous, **ctx)
      when Prism::CallNode
        walk_call(node, nesting, out, **ctx)
      else
        node.compact_child_nodes.each { |child| walk(child, nesting, out, **ctx) }
      end
    end

    # `define_method(:m) { ... }` is a method definition: the block body is
    # the method body, and re-evaluating the whole call redefines the method
    # on the enclosing owner (#194). Only a bare call with a literal name and
    # a block counts; a computed name, an explicit receiver, or a lambda
    # argument says nothing the finder can name.
    # A define_method subject's body is its block; any other call is walked
    # through its children.
    def walk_call(node, nesting, out, **ctx)
      return walk_children(node, nesting, out, **ctx) unless define_method_subject?(node)

      in_sclass = nesting.last&.sclass? || false
      owner = owner_path(nesting)
      owner ||= ANONYMOUS_OWNER if ctx[:in_block]
      return walk_children(node, nesting, out, **ctx) unless owner

      name = node.arguments.arguments.first.unescaped.to_sym
      subject = Subject.new(name: name, owner: owner, singleton: in_sclass, sclass: in_sclass,
                            file: ctx[:file], node: node, file_source: ctx[:source], nesting: nesting,
                            frozen_literals: ctx[:frozen], sig_span: nil)
      subject.skip_reason = "defined inside a block" if ctx[:in_block]
      out << subject
    end

    # Statements carry `previous` so a def can see the sig comment above it.
    def walk_statements(node, nesting, out, **ctx)
      previous_child = nil
      node.body.each do |child|
        walk(child, nesting, out, previous: previous_child, **ctx)
        previous_child = child
      end
    end

    def walk_children(node, nesting, out, **ctx)
      node.compact_child_nodes.each { |child| walk(child, nesting, out, **ctx) }
    end

    def define_method_subject?(node)
      return false unless node.name == :define_method && node.receiver.nil?
      return false unless node.block.is_a?(Prism::BlockNode)

      # With two arguments the second is the body and the block is dead code.
      return false unless node.arguments&.arguments&.size == 1

      name_arg = node.arguments.arguments.first
      name_arg.is_a?(Prism::SymbolNode) || name_arg.is_a?(Prism::StringNode)
    end

    # `Point = Data.define(:x) do ... end`: the defs belong to Point. Only the
    # four core factories count, called on the bare constant; any other call
    # that takes a block says nothing about the class it returns.
    def walk_constant_assignment(node, nesting, out, **ctx)
      call = node.value
      return node.compact_child_nodes.each { |child| walk(child, nesting, out, **ctx) } unless class_factory?(call)

      # The receiver and arguments stay in the enclosing scope; only the
      # factory's own block belongs to the new class. The block's body is
      # walked directly, not as a block: the factory names its class, so the
      # defs re-evaluate through X.class_eval and are ordinary subjects
      # (#290), while a block nested deeper still marks its defs skipped.
      (call.compact_child_nodes - [call.block]).each { |child| walk(child, nesting, out, **ctx) }
      walk(call.block.body, lexical_nesting(nesting) + [Scope.new(kind: :factory, path: node.name.to_s)], out, **ctx)
    end

    # Constant-introducing declarations (class/module keywords and factory
    # assignments) bind on the enclosing lexical scope: factory blocks open
    # none, so their scopes never join a new constant's path (#339).
    def lexical_nesting(nesting)
      nesting.reject(&:factory?)
    end

    def class_factory?(call)
      return false unless call.is_a?(Prism::CallNode) && call.block.is_a?(Prism::BlockNode)
      return false unless call.receiver.is_a?(Prism::ConstantReadNode)

      CLASS_FACTORIES[call.receiver.name] == call.name
    end

    def walk_singleton_class(node, nesting, out, **ctx)
      return unless node.expression.is_a?(Prism::SelfNode)
      return if nesting.empty? || nesting.last.sclass?

      walk(node.body, nesting + [Scope.new(kind: :sclass, path: "self")], out, **ctx)
    end

    def add_subject(node, nesting, out, file:, source:, frozen:, previous: nil, in_block: false)
      in_sclass = nesting.last&.sclass? || false
      # `def self.x` inside `class << self`, and `def obj.x`, are not subjects.
      return unless node.receiver.nil? || (node.receiver.is_a?(Prism::SelfNode) && !in_sclass)

      singleton = in_sclass || !node.receiver.nil?
      owner = owner_path(nesting)
      owner ||= ANONYMOUS_OWNER if in_block
      return unless owner

      subject = Subject.new(name: node.name, owner: owner, singleton: singleton, sclass: in_sclass,
                            file: file, node: node, file_source: source, nesting: nesting,
                            frozen_literals: frozen, sig_span: sig_span(previous))
      subject.skip_reason = "defined inside a block" if in_block
      out << subject
    end

    # The byte span of a `sig { ... }` or `T.sig { ... }` call on the lines
    # right before the def, when there is one.
    def sig_span(previous)
      return nil unless previous.is_a?(Prism::CallNode) && previous.name == :sig && previous.block
      return nil unless previous.receiver.nil? || previous.receiver.slice == "T"

      [previous.location.start_offset, previous.location.end_offset]
    end

    # Lexical path of the enclosing class/module. `class ::Foo` restarts at the top.
    def owner_path(nesting)
      parts = nesting.reject(&:sclass?).map(&:path)
      return nil if parts.empty?

      parts.each_with_object([]) do |path, acc|
        acc.clear if path.start_with?("::")
        acc << path.delete_prefix("::")
      end.join("::")
    end

    def mark_refinements(subjects, program)
      return unless uses_refinements?(program)

      subjects.each { |subject| subject.skip_reason = "refinements" }
    end

    def uses_refinements?(node)
      return true if node.is_a?(Prism::CallNode) && node.name == :using && node.receiver.nil?

      node.compact_child_nodes.any? { |child| uses_refinements?(child) }
    end
  end
end
