# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "subject"

module Saboteur
  # Finds `def` methods in a Ruby file with Prism.
  #
  # Included: instance methods and `def self.x` inside a class or module,
  # defs inside `class << self`, and defs passed to a receiverless call such
  # as `private def x`. Skipped: top-level defs, defs nested in defs, defs in
  # blocks (`Class.new do`, `included do`), and `def obj.x` for obj != self.
  class SubjectFinder
    Parsed = Data.define(:subjects, :errors)

    def call(file)
      source = File.binread(file)
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

    def walk(node, nesting, out, **ctx)
      case node
      when nil, Prism::BlockNode, Prism::LambdaNode
        nil
      when Prism::ModuleNode
        walk(node.body, nesting + [Scope.new(kind: :module, path: node.constant_path.slice)], out, **ctx)
      when Prism::ClassNode
        walk(node.body, nesting + [Scope.new(kind: :class, path: node.constant_path.slice)], out, **ctx)
      when Prism::SingletonClassNode
        walk_singleton_class(node, nesting, out, **ctx)
      when Prism::DefNode
        add_subject(node, nesting, out, **ctx)
      else
        node.compact_child_nodes.each { |child| walk(child, nesting, out, **ctx) }
      end
    end

    def walk_singleton_class(node, nesting, out, **ctx)
      return unless node.expression.is_a?(Prism::SelfNode)
      return if nesting.empty? || nesting.last.sclass?

      walk(node.body, nesting + [Scope.new(kind: :sclass, path: "self")], out, **ctx)
    end

    def add_subject(node, nesting, out, file:, source:, frozen:)
      in_sclass = nesting.last&.sclass? || false
      # `def self.x` inside `class << self`, and `def obj.x`, are not subjects.
      return unless node.receiver.nil? || (node.receiver.is_a?(Prism::SelfNode) && !in_sclass)

      singleton = in_sclass || !node.receiver.nil?
      owner = owner_path(nesting)
      return unless owner

      out << Subject.new(name: node.name, owner: owner, singleton: singleton, sclass: in_sclass,
                         file: file, node: node, file_source: source, nesting: nesting,
                         frozen_literals: frozen)
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
