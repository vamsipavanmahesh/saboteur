# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"

module Saboteur
  module MutationSource
    # What a method's Sorbet `sig` says about its return value, so mutants
    # that would return nil from a type that excludes nil can be left out.
    # Sorbet's runtime check turns such a mutant into a TypeError, which any
    # test that calls the method "kills": noise, not evidence.
    #
    # The answer is deliberately conservative. Only a return type that
    # certainly excludes nil counts: a class that nil is not an instance of
    # (resolved when the mutants are generated), or T::Boolean, T::Array[...]
    # and the like. Aliases, T.any, T.nilable, T.untyped and `void` all answer
    # "may be nil", so nothing is pruned for them.
    class DeclaredReturn
      GENERIC = /\AT::(Boolean|Array|Hash|Set|Range|Enumerable|Enumerator|Class)\b/

      def initialize(subject)
        @subject = subject
      end

      def excludes_nil?
        source = @subject.sig_source
        return false unless source

        type = returned_type(source)
        GENERIC.match?(type) || class_without_nil?(type)
      end

      private

      def returned_type(source)
        case returns_call(Prism.parse(source).value)&.arguments&.arguments
        in [Prism::Node => only] then only.slice
        else ""
        end
      end

      # The `returns(...)` call in the sig: `returns(X)` or `params(...).returns(X)`.
      def returns_call(node)
        return node if node.is_a?(Prism::CallNode) && node.name == :returns

        node.compact_child_nodes.each do |child|
          found = returns_call(child)
          return found if found
        end
        nil
      end

      def class_without_nil?(name)
        constant = resolve(name)
        constant.is_a?(Module) && !nil.is_a?(constant)
      end

      def resolve(name)
        candidates = [@subject.owner, nil].map { |scope| [scope, name].compact.join("::") }
        candidates.each do |path|
          return Object.const_get(path)
        rescue NameError
          next
        end
        nil
      end
    end
  end
end
