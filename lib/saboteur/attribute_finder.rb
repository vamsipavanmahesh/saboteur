# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "subject"

module Saboteur
  # Finds the methods attribute macros generate - attr_reader, attr_writer,
  # attr_accessor - so a --subject pattern naming one can be answered with
  # "defined by attr_reader, no body to mutate" instead of the
  # pattern-format hint (#373). The generated method has no body saboteur
  # can mutate, so it is never a mutation subject. Only a receiverless
  # call with literal symbol or string names defines anything nameable;
  # like SubjectFinder, a macro inside a block binds to an unknowable
  # self and is skipped.
  class AttributeFinder
    # One generated method: id follows Subject#id ("Owner#name",
    # "Owner.name", "Owner#name="), macro is the call that made it.
    Found = Data.define(:id, :macro)

    MACROS = %i[attr_reader attr_writer attr_accessor].freeze

    def call(file)
      result = Prism.parse(File.binread(file), filepath: file)
      return [] if result.failure?

      found = []
      walk(result.value, [], found)
      found
    end

    private

    def walk(node, nesting, out, in_block: false)
      return if node.nil?

      case node
      when Prism::BlockNode, Prism::LambdaNode
        walk(node.body, nesting, out, in_block: true)
      # A keyword class or module re-enters the lexical scope: a macro
      # inside binds on the class even when the class sits in a block
      # (mirrors ConstantSubjectFinder).
      when Prism::ModuleNode
        walk(node.body, nesting + [Scope.new(kind: :module, path: node.constant_path.slice)], out)
      when Prism::ClassNode
        walk(node.body, nesting + [Scope.new(kind: :class, path: node.constant_path.slice)], out)
      when Prism::SingletonClassNode
        walk_singleton_class(node, nesting, out)
      when Prism::CallNode
        record_macro(node, nesting, out, in_block: in_block)
        node.compact_child_nodes.each { |child| walk(child, nesting, out, in_block: in_block) }
      else
        node.compact_child_nodes.each { |child| walk(child, nesting, out, in_block: in_block) }
      end
    end

    # `class << self`: attribute macros inside define singleton methods on
    # the enclosing class (mirrors SubjectFinder's singleton defs).
    def walk_singleton_class(node, nesting, out)
      return unless node.expression.is_a?(Prism::SelfNode)
      return if nesting.empty? || nesting.last.sclass?

      walk(node.body, nesting + [Scope.new(kind: :sclass, path: "self")], out)
    end

    def record_macro(node, nesting, out, in_block:)
      return unless MACROS.include?(node.name) && node.receiver.nil? && node.block.nil?
      return if in_block

      owner = owner_path(nesting)
      return unless owner

      separator = nesting.last&.sclass? ? "." : "#"
      node.arguments&.arguments.to_a.each do |argument|
        name = macro_name(argument)
        next unless name

        generated_names(node.name, name).each do |method_name|
          out << Found.new(id: "#{owner}#{separator}#{method_name}", macro: node.name)
        end
      end
    end

    # The methods one macro call generates per named attribute: a reader, a
    # writer, or both for attr_accessor.
    def generated_names(macro, name)
      case macro
      when :attr_reader then [name]
      when :attr_writer then ["#{name}="]
      else [name, "#{name}="]
      end
    end

    def macro_name(argument)
      argument.unescaped if argument.is_a?(Prism::SymbolNode) || argument.is_a?(Prism::StringNode)
    end

    # Lexical path of the enclosing class/module; `class ::Foo` restarts at
    # the top. A `class << self` scope changes the separator, not the path.
    def owner_path(nesting)
      path = +""
      nesting.each do |scope|
        next if scope.sclass?

        segment = scope.path
        path.clear if segment.start_with?("::")
        path << "::" unless path.empty?
        path << segment.delete_prefix("::")
      end
      path.empty? ? nil : path
    end
  end
end
