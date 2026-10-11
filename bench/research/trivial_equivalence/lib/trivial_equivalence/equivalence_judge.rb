# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module TrivialEquivalence
  # Reports whether a mutated file compiles to the same normalized instruction
  # fingerprint as the original. Whole files are compared, so nested sequences
  # and the exception tables of every method are covered. Any doubt is
  # :no_match.
  class EquivalenceJudge
    def initialize(level:)
      @level = level
      @fingerprint = InstructionSequenceFingerprint.new(level: level)
    end

    def judge(original_source:, mutated_source:, path:)
      original = compile(original_source, path)
      return no_match(:original_compile_failed) unless original

      mutated = compile(mutated_source, path)
      return no_match(:mutated_compile_failed) unless mutated
      return no_match(:reflection) if @level == :relaxed && reflective?(original_source, path)

      same = @fingerprint.call(original) == @fingerprint.call(mutated)
      same ? Verdict.new(status: :fingerprint_match, reason: :identical_instruction_sequences) : no_match(:different)
    end

    private

    def compile(source, path)
      CompilerPin.compile(source, path)
    rescue SyntaxError, ArgumentError, EncodingError
      nil
    end

    def reflective?(source, path)
      ReflectionScan.new(source, path).findings.any?
    end

    def no_match(reason)
      Verdict.new(status: :no_match, reason: reason)
    end
  end
end
