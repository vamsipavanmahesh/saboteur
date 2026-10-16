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
  # `Shop::RULES` path matches by its full spelling. Reads reached through a
  # superclass, `const_get`, or a compact `class Shop::Item` scope are not
  # resolved: a constant only read that way finds no consumer here, and the
  # run reports it as ran-at-load instead of guessing.
  module ConstantReads
    module_function

    # { "/abs/file.rb" => [1-based lines] } for the files that read the
    # constant. Only files whose text mentions the name are parsed.
    def across(files, constant)
      mention = /\b#{Regexp.escape(constant.name.to_s)}\b/
      files.each_with_object({}) do |file, hits|
        source = File.binread(file)
        next unless mentions?(source, mention)

        lines = lines_in(source, constant)
        hits[file] = lines unless lines.empty?
      end
    end

    def mentions?(source, mention)
      Text.utf8_identity(source).match?(mention)
    rescue Encoding::CompatibilityError, ArgumentError
      false
    end

    def lines_in(source, constant)
      result = Prism.parse(source)
      return [] if result.failure?

      lines = []
      walk(result.value, [], constant, lines)
      lines.uniq.sort
    end

    def walk(node, nesting, constant, lines)
      return if node.nil?

      case node
      when Prism::ConstantReadNode
        lines << node.location.start_line if bare_match?(node, nesting, constant)
      when Prism::ConstantPathNode
        # `Shop::RULES` holds no ConstantReadNode for RULES, only for Shop;
        # match the path's full spelling.
        lines << node.location.start_line if node.slice.delete_prefix("::") == constant.id.to_s
        walk_children(node, nesting, constant, lines)
      when Prism::ModuleNode, Prism::ClassNode
        walk(node.body, nesting + [node.constant_path.slice.delete_prefix("::")], constant, lines)
      else
        # `class << self` and blocks do not add a lexical constant scope
        # worth separating here.
        walk_children(node, nesting, constant, lines)
      end
    end

    def walk_children(node, nesting, constant, lines)
      node.compact_child_nodes.each { |child| walk(child, nesting, constant, lines) }
    end

    # A bare `RULES` reads this constant when the read's scope is the
    # constant's owner or nested under it, or the constant is top-level.
    def bare_match?(node, nesting, constant)
      return false unless node.name == constant.name

      path = nesting.join("::")
      constant.owner.nil? || path == constant.owner || path.start_with?("#{constant.owner}::")
    end
  end
end
