# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Execution
    # Redefines a subject's method from (possibly mutated) text, in the running
    # process, without touching the file on disk.
    #
    # Strategies (see docs/design.md 6.1):
    #   class_eval - owner.class_eval(text, file, line), as specified. Constants
    #                from enclosing modules are not in lexical scope.
    #   nesting    - rebuild the original `module A; class B` nesting on one line
    #                and eval at top level, so constant lookup matches the file.
    #
    # A subject named in whole_file skips both: the child evaluates the whole
    # file with the mutated method spliced in, the way mutineer does. That is
    # the way in for methods surgical re-evaluation refuses, at a price: the
    # file's top-level code runs again in the child, so load-time side effects
    # repeat and constants it assigns are rebuilt. It reaches only methods
    # SubjectFinder already finds.
    #
    # Both keep the original file and line numbers, carry a frozen_string_literal
    # magic comment, and restore the method's visibility afterwards.
    class Reevaluator
      STRATEGIES = %w[class_eval nesting].freeze
      FROZEN_HEADER = "# frozen_string_literal: true\n"

      def initialize(strategy = "nesting", whole_file: [])
        raise Error, "unknown reeval strategy: #{strategy}" unless STRATEGIES.include?(strategy.to_s)

        @strategy = strategy.to_s
        @whole_file = whole_file
      end

      # Where the method the child ended up with is defined, as "file:line",
      # when that is not the subject's own def: a later definition in the same
      # file replaced it (or none is left), so the mutant could never run.
      # nil when the subject is not whole-file, or its def is the one in place.
      def replaced_definition(subject)
        return nil unless whole_file?(subject)

        owner = resolve_owner(subject)
        target = subject.singleton ? owner.singleton_class : owner
        method = target.instance_method(subject.name)
        # A def-time wrapper (a sorbet sig) replaces the method; its own
        # source_location is the wrapper's, not the def's.
        file, line = (Wrapper.original_def(method) || method).source_location
        return nil if file == subject.file && line == subject.start_line

        file ? "#{file}:#{line}" : "no Ruby definition"
      rescue StandardError
        "no definition"
      end

      # True when the subject's id matches a whole_file entry (exact or a
      # File.fnmatch glob).
      def whole_file?(subject)
        @whole_file.any? { |pattern| File.fnmatch?(pattern, subject.id) }
      end

      # prefix: source evaluated right before the def text, at the lines it
      # occupies in the file - a sorbet `sig { ... }` call, so the wrapper
      # gem re-wraps the mutant and its runtime checks stay on.
      def call(subject, text, prefix: nil)
        return eval_whole_file(subject, text) if whole_file?(subject)

        owner = resolve_owner(subject)
        target = subject.singleton ? owner.singleton_class : owner
        visibility = visibility_of(target, subject.name)
        module_function = module_function?(owner, subject)
        copy_visibility = visibility_of(owner.singleton_class, subject.name) if module_function
        aliases = aliases_of(target, subject.name)

        extra_lines = prefix ? prefix.count("\n") + 1 : 0
        full_text = prefix ? "#{prefix}\n#{text}" : text
        if @strategy == "nesting"
          eval_nested(subject, full_text, extra_lines)
        else
          eval_in_owner(owner, subject, full_text, extra_lines)
        end

        restore(owner, target, subject.name, visibility, copy_visibility)
        repoint(target, subject.name, aliases)
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
        return false unless owner.singleton_class.method_defined?(subject.name, false) ||
                            owner.singleton_class.private_method_defined?(subject.name, false)

        owner.instance_method(subject.name).source_location ==
          owner.singleton_class.instance_method(subject.name).source_location
      end

      # The file as it is on disk, with the method's bytes replaced by text,
      # evaluated at top level under the file's own name and first line.
      # Redefinition warnings are expected and silenced.
      def eval_whole_file(subject, text)
        source = subject.file_source.dup.force_encoding(Encoding::UTF_8)
        spliced = source.byteslice(0, subject.start_byte) + text + source.byteslice(subject.end_byte..)
        verbose = $VERBOSE
        $VERBOSE = nil
        TOPLEVEL_BINDING.eval(spliced, subject.file, 1)
      ensure
        $VERBOSE = verbose
      end

      def eval_in_owner(owner, subject, text, extra_lines)
        code, line = with_magic_comment(subject, text, extra_lines)
        eval_target = subject.sclass ? owner.singleton_class : owner
        eval_target.class_eval(code, subject.file, line)
      end

      def eval_nested(subject, text, extra_lines)
        headers = subject.nesting.map(&:header)
        wrapped = "#{headers.join('; ')}; #{text}; #{(['end'] * headers.size).join('; ')}"
        code, line = with_magic_comment(subject, wrapped, extra_lines)
        TOPLEVEL_BINDING.eval(code, subject.file, line)
      end

      # The first line of code sits extra_lines above the def, so the def
      # keeps its file line numbers.
      def with_magic_comment(subject, code, extra_lines)
        return [code, subject.start_line - extra_lines] unless subject.frozen_literals

        [FROZEN_HEADER + code, subject.start_line - extra_lines - 1]
      end

      # Methods defined with alias/alias_method copy the old body. Callers
      # that use the alias would never see the mutant, which would then
      # survive for no reason. Only aliases of the current definition count
      # (same source location): an alias taken before the method was
      # redefined keeps the older body on purpose. Returns { alias => visibility }.
      def aliases_of(target, name)
        current = target.instance_method(name).source_location
        names = target.instance_methods(false) + target.private_instance_methods(false)
        names.each_with_object({}) do |other, found|
          next if other == name

          method = target.instance_method(other)
          next unless method.original_name == name && method.source_location == current

          found[other] = visibility_of(target, other)
        end
      end

      def repoint(target, name, aliases)
        aliases.each do |other, visibility|
          target.send(:alias_method, other, name)
          target.send(visibility, other)
        end
      end

      def restore(owner, target, name, visibility, copy_visibility)
        if copy_visibility
          owner.send(:module_function, name)
          owner.singleton_class.send(copy_visibility, name)
        elsif visibility != :public
          target.send(visibility, name)
        end
      end
    end
  end
end
