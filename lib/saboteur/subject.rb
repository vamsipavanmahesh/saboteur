# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # One lexical scope enclosing a def: `module X`, `class X` or `class << self`.
  Scope = Data.define(:kind, :path) do
    def header
      case kind
      when :module then "module #{path}"
      when :class then "class #{path}"
      when :sclass then "class << self"
      end
    end

    def sclass?
      kind == :sclass
    end
  end

  # A method defined with `def`: the unit saboteur mutates.
  #
  # Byte offsets index the file as read from disk. singleton is true for
  # `def self.x` and for defs inside `class << self`; sclass is true only for
  # the latter, because the def text must then be evaluated on the singleton.
  class Subject
    attr_reader :name, :owner, :singleton, :sclass, :file, :start_byte, :end_byte,
                :start_line, :end_line, :nesting, :node, :file_source, :frozen_literals
    attr_accessor :skip_reason

    def initialize(name:, owner:, singleton:, sclass:, file:, node:, file_source:, nesting:, frozen_literals:)
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
      @skip_reason = nil
    end

    def id
      "#{owner}#{singleton ? '.' : '#'}#{name}"
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

    def contains_line?(line)
      line.between?(start_line, end_line)
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

    def to_s
      id
    end

    private

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
