# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "subject"
require_relative "deep_source"

module Saboteur
  # Finds `def` methods in a Ruby file with Prism.
  #
  # Included: instance methods and `def self.x` inside a class or module,
  # defs inside `class << self`, and defs passed to a receiverless call such
  # as `private def x`. Skipped: top-level defs and defs nested in defs.
  # `def Const.m` is found but marked skipped (a constant receiver names an
  # owner saboteur cannot re-evaluate through, #627); `def obj.x` for any
  # other obj is dropped, as before. Defs in blocks (`included do`, builders)
  # are found but marked skipped ("defined inside a block"), so the report
  # names them instead of leaving them out - except the four core class
  # factories: `X = Data.define`, `Struct.new`, `Class.new` or `Module.new`
  # with a block names X as the owner, and its defs are ordinary subjects
  # that re-evaluate through X.class_eval (#290). Known registry DSLs work
  # the same way: `Ohai.plugin(:Network) do` and
  # `Puppet::Type.type(:t).provide :p do` class_eval a class registered
  # under a predictable constant, so their defs re-evaluate through it
  # (#700). Any other block, and a `A::X = ...` target, keeps the
  # enclosing owner or the placeholder.
  class SubjectFinder
    Parsed = Data.define(:subjects, :errors)
    ANONYMOUS_OWNER = "(anonymous block)"
    CALL_DEFINED_SINGLETONS = %i[scope define_singleton_method].freeze
    CLASS_FACTORIES = { Data: :define, Struct: :new, Class: :new, Module: :new }.freeze

    # source: the text to parse when it is not the file on disk (the file as
    # it was at an earlier commit).
    def call(file, source: File.binread(file))
      result = Prism.parse(source, filepath: file)
      return Parsed.new(subjects: [], errors: result.errors.map(&:message)) if result.failure?

      DeepSource.check!(result.value, file)

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
      return walk_heredoc_eval(node, nesting, out, **ctx) if heredoc_eval?(node)

      dsl_owner = registry_dsl_owner(node)
      return walk_registry_dsl(node, dsl_owner, nesting, out, **ctx) if dsl_owner

      return walk_children(node, nesting, out, **ctx) unless call_defined_method?(node)

      in_sclass = nesting.last&.sclass? || false
      owner = owner_path(nesting)
      owner ||= ANONYMOUS_OWNER if ctx[:in_block]
      return walk_children(node, nesting, out, **ctx) unless owner

      name = node.arguments.arguments.first.unescaped.to_sym
      # scope and define_singleton_method define on the class itself;
      # define_method follows the surrounding nesting like a def (#194).
      singleton = in_sclass || CALL_DEFINED_SINGLETONS.include?(node.name)
      subject = Subject.new(name: name, owner: owner, singleton: singleton, sclass: in_sclass,
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

    # `class_eval <<-RUBY ... RUBY` with a non-interpolated heredoc defines
    # methods on the enclosing owner (#544). Only a bare call with one
    # heredoc argument counts: an explicit receiver names another owner, and
    # an interpolated heredoc does not map to file bytes 1:1, so it stays on
    # the code-in-strings warning (#467).
    def heredoc_eval?(node)
      return false unless %i[class_eval module_eval].include?(node.name) && node.receiver.nil? && node.block.nil?

      arguments = node.arguments&.arguments
      return false unless arguments&.size == 1

      heredoc = arguments.first
      heredoc.is_a?(Prism::StringNode) && heredoc.opening_loc&.slice&.start_with?("<<")
    end

    # The heredoc body's bytes sit in the real file 1:1, so blanking every
    # byte outside the body (keeping newlines) parses the defs at their
    # real offsets and lines: mutants apply through the ordinary file-bytes
    # path. The enclosing nesting supplies the owner. A body that does not
    # parse defines nothing.
    def walk_heredoc_eval(node, nesting, out, **ctx)
      location = node.arguments.arguments.first.content_loc
      virtual = blank_outside(ctx[:source], location.start_offset...location.end_offset)
      result = Prism.parse(virtual, filepath: ctx[:file])
      return if result.failure?

      walk(result.value, nesting, out, **ctx)
    end

    # source with every byte outside range spaced over, except newlines:
    # offsets and lines inside range stay exactly as in the real file.
    def blank_outside(source, range)
      source.bytes.each_with_index.map { |byte, index| range.cover?(index) || byte == 10 ? byte : 32 }.pack("C*")
            .force_encoding(source.encoding)
    end

    def define_method_subject?(node)
      return false unless node.name == :define_method && node.receiver.nil?
      return false unless node.block.is_a?(Prism::BlockNode)

      # With two arguments the second is the body and the block is dead code.
      return false unless node.arguments&.arguments&.size == 1

      name_arg = node.arguments.arguments.first
      name_arg.is_a?(Prism::SymbolNode) || name_arg.is_a?(Prism::StringNode)
    end

    # Calls that define a method, all with a literal first argument for the
    # name: define_method (instance, or singleton inside class << self) and
    # the two class-level shapes the human-essentials dogfood exposed,
    # `scope :name, -> { ... }` and define_singleton_method (#194). The
    # whole call is the subject's source and re-evaluates on the owner.
    def call_defined_method?(node)
      return false unless node.receiver.nil?
      return false unless literal_name?(node)

      case node.name
      when :define_method then define_method_subject?(node)
      when :define_singleton_method then lambda_body?(node) || block_only?(node)
      # Rails scope: exactly a literal name and a lambda body.
      when :scope then lambda_body?(node) && node.arguments.arguments.size == 2
      else false
      end
    end

    def literal_name?(node)
      name_arg = node.arguments&.arguments&.first
      name_arg.is_a?(Prism::SymbolNode) || name_arg.is_a?(Prism::StringNode)
    end

    def lambda_body?(node)
      node.block.nil? && node.arguments&.arguments&.last.is_a?(Prism::LambdaNode)
    end

    def block_only?(node)
      node.block.is_a?(Prism::BlockNode) && node.arguments&.arguments&.size == 1
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

    # Registry DSLs whose block class_evals a fresh class registered under a
    # predictable constant (#700): `Ohai.plugin(:Network)` registers
    # Ohai::NamedPlugin::Network, and `Puppet::Type.type(:package).provide
    # :pacman` registers Puppet::Type::Package::ProviderPacman. Like the core
    # class factories (#290) the block's defs re-evaluate through that
    # constant, so they are ordinary subjects. The registry names its class
    # at the top level, so the path restarts at `::` whatever the enclosing
    # scope. A call the registry does not know, or one with a non-literal
    # name, keeps the ordinary "defined inside a block" skip; extend the
    # list here as more frameworks need it.
    def registry_dsl_owner(node)
      return unless node.block.is_a?(Prism::BlockNode)

      if node.name == :plugin && node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Ohai
        name = symbol_argument(node.arguments)
        "::Ohai::NamedPlugin::#{camelize(name)}" if name
      elsif node.name == :provide && (type = puppet_type_call(node.receiver))
        name = symbol_argument(node.arguments)
        "::Puppet::Type::#{camelize(type)}::Provider#{camelize(name)}" if name
      end
    end

    # `Puppet::Type.type(:package)`: the type name the provider attaches to.
    def puppet_type_call(receiver)
      return unless receiver.is_a?(Prism::CallNode) && receiver.name == :type && receiver.block.nil?
      return unless receiver.receiver.is_a?(Prism::ConstantPathNode) && receiver.receiver.slice == "Puppet::Type"

      symbol_argument(receiver.arguments)
    end

    def symbol_argument(arguments)
      first = arguments&.arguments&.first
      first.unescaped if first.is_a?(Prism::SymbolNode)
    end

    def camelize(name)
      name.split("_").map!(&:capitalize).join
    end

    # The receiver and arguments stay in the enclosing scope; only the DSL's
    # own block belongs to the registered class. Walked like a factory block
    # (#290): a block nested deeper still marks its defs skipped, and a DSL
    # call that itself sits in a block names the registry class but keeps
    # the skip, since the registration may never run.
    def walk_registry_dsl(node, owner, nesting, out, **ctx)
      (node.compact_child_nodes - [node.block]).each { |child| walk(child, nesting, out, **ctx) }
      walk(node.block.body, lexical_nesting(nesting) + [Scope.new(kind: :factory, path: owner)], out, **ctx)
    end

    # Constant-introducing declarations (class/module keywords and factory
    # assignments) bind on the enclosing lexical scope: factory blocks open
    # none, so their scopes never join a new constant's path (#339) - unless
    # an sclass follows the factory: `class << self` inside a factory block
    # attaches to the factory's class at runtime (class_eval sets self), and
    # the sclass needs the factory's path to name that attachment (#438).
    def lexical_nesting(nesting)
      nesting.each_with_index.reject do |scope, index|
        scope.factory? && nesting[(index + 1)..].none?(&:sclass?)
      end.map(&:first)
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
      # `def self.x` inside `class << self` is not a subject. A def with
      # any other explicit receiver goes through the report-it door (#627).
      if node.receiver && !(node.receiver.is_a?(Prism::SelfNode) && !in_sclass)
        return report_receiver_def(node, out, file: file, source: source, frozen: frozen)
      end

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

    # `def Const.m` defines a singleton on the named constant; re-evaluating
    # it through the enclosing owner would not redefine it. Emit it as a
    # skipped subject so the report names it (#627) instead of the run
    # reading as "nothing to mutate". A receiver saboteur cannot name (a
    # local, a call result) stays out, as before.
    def report_receiver_def(node, out, file:, source:, frozen:)
      # Ruby only allows a bare constant here (`def A::B.m` is a syntax
      # error), so the receiver is a ConstantReadNode or nothing we name.
      receiver = node.receiver
      return unless receiver.is_a?(Prism::ConstantReadNode)

      owner = receiver.name.to_s

      subject = Subject.new(name: node.name, owner: owner, singleton: true, sclass: false,
                            file: file, node: node, file_source: source, nesting: [],
                            frozen_literals: frozen, sig_span: nil)
      subject.skip_reason = "constant-receiver def"
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
    # A bare `class << self` scope leaves the owner alone (its defs are the
    # attached class's singleton methods), but a factory constant assigned
    # through it binds on the singleton class (#352), so the sclass renders
    # as a `singleton_class` path segment when a factory scope sits after it
    # (#406): `Host.singleton_class::Widget`, mirroring the constant side
    # (#380).
    def owner_path(nesting)
      segments = nesting.each_with_index.filter_map do |scope, index|
        if scope.sclass?
          :singleton_class if nesting[(index + 1)..].any?(&:factory?)
        else
          scope.path
        end
      end
      return nil if segments.empty?

      segments.each_with_object(+"") do |segment, out|
        if segment == :singleton_class
          out << ".singleton_class"
        else
          out.clear if segment.start_with?("::")
          out << "::" unless out.empty?
          out << segment.delete_prefix("::")
        end
      end
    end

    def mark_refinements(subjects, program)
      RefinementActivations.mark(subjects, program)
    end
  end
end
