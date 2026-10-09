# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Redefines a subject's method from (possibly mutated) text, in the running
  # process, without touching the file on disk.
  #
  # Strategies (see docs/design.md 6.1):
  #   class_eval - owner.class_eval(text, file, line), as specified. Constants
  #                from enclosing modules are not in lexical scope.
  #   nesting    - rebuild the original `module A; class B` nesting on one line
  #                and eval at top level, so constant lookup matches the file.
  #
  # Both keep the original file and line numbers, carry a frozen_string_literal
  # magic comment, and restore the method's visibility afterwards.
  class Reevaluator
    STRATEGIES = %w[class_eval nesting].freeze
    FROZEN_HEADER = "# frozen_string_literal: true\n"

    def initialize(strategy = "class_eval")
      raise Error, "unknown reeval strategy: #{strategy}" unless STRATEGIES.include?(strategy.to_s)

      @strategy = strategy.to_s
    end

    def call(subject, text)
      owner = resolve_owner(subject)
      target = subject.singleton ? owner.singleton_class : owner
      visibility = visibility_of(target, subject.name)
      module_function = module_function?(owner, subject)

      @strategy == "nesting" ? eval_nested(subject, text) : eval_in_owner(owner, subject, text)

      restore(owner, target, subject.name, visibility, module_function)
    end

    # Resolves the subject's owner the way Ruby would resolve the nesting in
    # the file. const_get also triggers autoload (Zeitwerk) before any reopening.
    def resolve_owner(subject)
      scopes = [Object]
      subject.nesting.reject(&:sclass?).each do |scope|
        scopes << resolve_path(scope.path, scopes)
      end
      owner = scopes.last
      raise Error, "#{subject.owner} is not a class or module" unless owner.is_a?(Module)

      owner
    rescue NameError => e
      raise Error, "cannot resolve #{subject.owner}: #{e.message}"
    end

    private

    def resolve_path(path, scopes)
      return Object.const_get(path.delete_prefix("::")) if path.start_with?("::")

      first, *rest = path.split("::")
      base = if rest.empty?
               # `class B` inside `module A` opens A::B (or ::B at top level).
               scopes.last.const_get(first, false)
             else
               lexical_lookup(first, scopes)
             end
      rest.reduce(base) { |mod, name| mod.const_get(name, false) }
    end

    def lexical_lookup(name, scopes)
      found = scopes.reverse.find { |scope| scope.const_defined?(name, false) }
      (found || Object).const_get(name, false)
    end

    def visibility_of(target, name)
      if target.private_method_defined?(name, false) then :private
      elsif target.protected_method_defined?(name, false) then :protected
      else :public
      end
    end

    def module_function?(owner, subject)
      return false if subject.singleton || owner.is_a?(Class)
      return false unless owner.private_method_defined?(subject.name, false)
      return false unless owner.singleton_class.public_method_defined?(subject.name, false)

      owner.instance_method(subject.name).source_location ==
        owner.singleton_class.instance_method(subject.name).source_location
    end

    def eval_in_owner(owner, subject, text)
      code, line = with_magic_comment(subject, text)
      eval_target = subject.sclass ? owner.singleton_class : owner
      eval_target.class_eval(code, subject.file, line)
    end

    def eval_nested(subject, text)
      headers = subject.nesting.map(&:header)
      wrapped = "#{headers.join('; ')}; #{text}; #{(['end'] * headers.size).join('; ')}"
      code, line = with_magic_comment(subject, wrapped)
      TOPLEVEL_BINDING.eval(code, subject.file, line)
    end

    def with_magic_comment(subject, code)
      return [code, subject.start_line] unless subject.frozen_literals

      [FROZEN_HEADER + code, subject.start_line - 1]
    end

    def restore(owner, target, name, visibility, module_function)
      if module_function
        owner.send(:module_function, name)
      elsif visibility != :public
        target.send(visibility, name)
      end
    end
  end
end
