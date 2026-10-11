# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module TrivialEquivalence
  # Reduces an instruction sequence (RubyVM::InstructionSequence#to_a) to the
  # parts that decide behavior, recursively through nested sequences (blocks,
  # methods, classes, rescue and ensure bodies in the catch table).
  #
  # Kept in both levels: the instructions with all operands (so every literal,
  # constant name, method name, call flag and branch target), the local
  # variable table, the parameter description, the catch (exception) table,
  # the sequence type and the label.
  #
  # Dropped in both levels: file paths, node ids and code columns. They only
  # feed tooling.
  #
  # Level :strict keeps line numbers. Level :relaxed drops them.
  class InstructionSequenceFingerprint
    NESTED_MARKER = "YARVInstructionSequence/SimpleDataFormat"
    DROPPED_MISC = %i[node_id code_location node_ids].freeze

    def initialize(level:)
      raise ArgumentError, "unknown level #{level.inspect}" unless %i[strict relaxed].include?(level)

      @relaxed = level == :relaxed
    end

    def call(instruction_sequence)
      normalize_sequence(instruction_sequence.to_a)
    end

    private

    def normalize_sequence(raw)
      magic, major, minor, format, misc, label, _path, _absolute_path, first_line, type, locals, params, catches,
        body = raw
      [magic, major, minor, format, misc.except(*DROPPED_MISC), label, (@relaxed ? nil : first_line), type, locals,
       params, normalize(catches), normalize_body(body)]
    end

    # Top-level integers in the body are line markers.
    def normalize_body(body)
      kept = @relaxed ? body.grep_v(Integer) : body
      normalize(kept)
    end

    def normalize(value)
      case value
      when Array
        nested_sequence?(value) ? normalize_sequence(value) : value.map { |element| normalize(element) }
      when Hash then value.transform_values { |element| normalize(element) }
      else value
      end
    end

    def nested_sequence?(array)
      array.first == NESTED_MARKER && array.size == 14
    end
  end
end
