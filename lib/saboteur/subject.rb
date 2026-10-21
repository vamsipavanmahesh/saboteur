# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # One lexical scope enclosing a def: `module X`, `class X`, a class-factory
  # block (`X = Data.define(:x) do`) or `class << self`.
  Scope = Data.define(:kind, :path) do
    # A factory scope wraps the def in `X.class_eval do`: reopening it as
    # `class X` would fight the generated class (a Module.new X is not even
    # a class), while class_eval adds the method to the class already there.
    def header
      case kind
      when :module then "module #{path}"
      when :class then "class #{path}"
      when :factory then "#{path}.class_eval do"
      when :sclass then "class << self"
      end
    end

    def sclass?
      kind == :sclass
    end

    # A factory scope names a runtime owner (the generated class) but opens
    # no lexical constant scope: `Outer = Class.new do Inner = ... end` binds
    # Inner on the enclosing lexical scope, never on Outer (#339).
    def factory?
      kind == :factory
    end
  end

  # A method defined with `def`: the unit saboteur mutates.
  #
  # Byte offsets index the file as read from disk. singleton is true for
  # `def self.x` and for defs inside `class << self`; sclass is true only for
  # the latter, because the def text must then be evaluated on the singleton.
  class Subject
    attr_reader :name, :owner, :singleton, :sclass, :file, :start_byte, :end_byte,
                :start_line, :end_line, :nesting, :node, :file_source, :frozen_literals, :sig_span
    attr_accessor :skip_reason

    def initialize(name:, owner:, singleton:, sclass:, file:, node:, file_source:, nesting:, frozen_literals:,
                   sig_span: nil)
      @name = name
      @owner = owner
      @singleton = singleton
      @sclass = sclass
      @file = file
      @node = node
      @file_source = file_source
      @nesting = nesting
      @frozen_literals = frozen_literals
      @start_byte = node.location.start_offset
      @end_byte = node.location.end_offset
      @start_line = node.location.start_line
      @end_line = node.location.end_line
      @sig_span = sig_span
      @skip_reason = nil
    end

    # The `sig { ... }` call right before the def, when there is one. A
    # sorbet-wrapped method re-evaluates sig and def together, so the
    # runtime type checks stay on for the mutant (see Execution::Wrapper).
    def sig_source
      return nil unless @sig_span

      first, last = @sig_span
      file_source.byteslice(first, last - first).force_encoding(Encoding::UTF_8)
    end

    def id
      "#{owner}#{singleton ? '.' : '#'}#{name}"
    end

    # "path:line" for warnings, relative to the run root (or the full path
    # without one), so a skipped subject can be told apart from a real
    # subject sharing its id (#627).
    def location(root)
      file = root ? @file.delete_prefix("#{root}/") : @file
      "#{file}:#{start_line}"
    end

    # The gate sentence a scoped run prints when every subject was skipped
    # (#574); the location disambiguates a skipped subject from a real one
    # sharing its id (#627).
    def skipped_gate_sentence(reason, root)
      "error: #{Text.display_safe(id)} (#{Text.display_safe(location(root))}) was skipped (#{reason}), " \
        "so the change under test was not verified\n" \
        "help: run the specs that exercise it, or narrow the scope past it"
    end

    # The node whose children are the method's statements: the block body
    # for `define_method(:m) { ... }` (#194), the def body otherwise.
    def body_node
      return node.body unless node.is_a?(Prism::CallNode)

      # define_method carries its body in the block; scope and the lambda
      # form of define_singleton_method carry it in the lambda argument.
      lambda = node.arguments&.arguments&.find { |arg| arg.is_a?(Prism::LambdaNode) }
      (lambda || node.block)&.body
    end

    def source
      @source ||= file_source.byteslice(start_byte, end_byte - start_byte).force_encoding(Encoding::UTF_8)
    end

    # Text on the def's first line before it, and on its last line after it,
    # so diffs show whole lines with their indentation.
    def surrounding_text
      line_start = (file_source.byteslice(0, start_byte).rindex("\n") || -1) + 1
      line_end = file_source.index("\n", end_byte) || file_source.bytesize
      [file_source.byteslice(line_start, start_byte - line_start),
       file_source.byteslice(end_byte, line_end - end_byte)].map { |text| text.force_encoding(Encoding::UTF_8) }
    end

    # Lines whose execution means the method body ran. For a multi-line def
    # the def line itself runs at load time, so it is left out.
    def coverage_lines
      return [start_line] if start_line == end_line

      ((start_line + 1)..end_line).to_a
    end

    # Lines whose execution means the edited code ran: from the first line of
    # the innermost statement containing the edit to the edit's last line.
    # Pattern headers do not always record line events. Their enclosing case
    # and clause body supply execution evidence instead.
    # An edit outside every statement (signature, around the def, whole
    # body) maps to the whole method.
    def coverage_lines_for(edit)
      pattern_lines = pattern_coverage_lines(body_node, edit)
      return pattern_lines if pattern_lines

      statement = innermost_statement(body_node, edit.start_byte, edit.end_byte)
      return coverage_lines unless statement

      first = statement.location.start_line
      last = line_of([edit.end_byte - 1, edit.start_byte].max)
      (first..[last, first].max).to_a
    end

    # True when anything in the body can turn an error into a value: a
    # rescue or else clause, a modifier rescue, a nested begin/rescue.
    def recovers?
      rescuing?(body_node)
    end

    # The 1-based line of the file that holds this byte offset.
    def line_of(byte_offset)
      file_source.byteslice(0, byte_offset).count("\n") + 1
    end

    def contains_line?(line)
      line.between?(start_line, end_line)
    end

    # True when a changed-lines set intersects this subject's span. A
    # whole-file range answers by interval overlap in O(1) instead of a
    # per-line scan from line 1 for every subject.
    def overlaps_lines?(lines)
      if lines.is_a?(Range)
        lines.begin <= end_line && start_line <= lines.end
      else
        lines.any? { |line| contains_line?(line) }
      end
    end

    # Applies the mutation's edits to this method's text and returns the
    # mutated method text. Raises ArgumentError for edits outside the method
    # or overlapping each other.
    def apply(edits)
      text = file_source.byteslice(start_byte, end_byte - start_byte).b
      previous_start = nil
      edits.sort_by(&:start_byte).reverse_each do |edit|
        validate_edit!(edit, previous_start)
        previous_start = edit.start_byte
        relative = edit.start_byte - start_byte
        text = text.byteslice(0, relative) + edit.replacement.b + text.byteslice((edit.end_byte - start_byte)..)
      end
      text.force_encoding(Encoding::UTF_8)
    end

    # Def subjects prefer surgical re-evaluation; a ConstantSubject always
    # re-evaluates its whole file (there is no method to redefine).
    def whole_file_only?
      false
    end

    def to_s
      id
    end

    private

    def rescuing?(child)
      case child
      when nil, Prism::DefNode, Prism::ClassNode, Prism::ModuleNode then false
      when Prism::RescueModifierNode then true
      when Prism::BeginNode then !(child.rescue_clause.nil? && child.else_clause.nil?) || descend?(child)
      else descend?(child)
      end
    end

    def descend?(child)
      child.compact_child_nodes.any? { |grandchild| rescuing?(grandchild) }
    end

    # An interpolation's own statements (#{"..."}) are eager: they run on
    # the enclosing statement's lines, so they never demote it (#498). A
    # continuation line of a multi-line interpolated statement can lack a
    # per-example line hit, so attribution must span from the statement's
    # first line.
    def innermost_statement(node, start_byte, end_byte, found = nil, embedded: false)
      return found if node.nil?

      if node.is_a?(Prism::StatementsNode) && !embedded
        statement = node.body.find do |child|
          child.location.start_offset <= start_byte && end_byte <= child.location.end_offset
        end
        return found unless statement

        found = statement
        node = statement
      end
      node.compact_child_nodes.each do |child|
        next unless child.location.start_offset <= start_byte && end_byte <= child.location.end_offset

        return innermost_statement(child, start_byte, end_byte, found,
                                   embedded: embedded || node.is_a?(Prism::EmbeddedStatementsNode))
      end
      found
    end

    def pattern_coverage_lines(child, edit, case_line = nil)
      return nil unless child

      case_line = child.location.start_line if child.is_a?(Prism::CaseMatchNode)
      if child.is_a?(Prism::InNode) && contains_edit?(child.pattern, edit)
        return [case_line, child.location.start_line, child.statements&.location&.start_line].compact.uniq
      end

      child.compact_child_nodes.each do |nested|
        next unless contains_edit?(nested, edit)

        lines = pattern_coverage_lines(nested, edit, case_line)
        return lines if lines
      end
      nil
    end

    def contains_edit?(child, edit)
      child.location.start_offset <= edit.start_byte && edit.end_byte <= child.location.end_offset
    end

    def validate_edit!(edit, previous_start)
      unless File.expand_path(edit.file) == File.expand_path(file)
        raise ArgumentError, "edit for #{edit.file} applied to subject in #{file}"
      end
      unless edit.start_byte >= start_byte && edit.end_byte <= end_byte
        raise ArgumentError, "edit #{edit.start_byte}...#{edit.end_byte} is outside #{id} (#{start_byte}...#{end_byte})"
      end
      raise ArgumentError, "overlapping edits in mutation of #{id}" if previous_start && edit.end_byte > previous_start
    end
  end
end
