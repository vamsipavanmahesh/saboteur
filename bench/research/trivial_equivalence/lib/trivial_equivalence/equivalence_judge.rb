# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module TrivialEquivalence
  # Decides whether a mutated file compiles to the same instruction sequence
  # as the original. Whole files are compared, so nested sequences and the
  # exception tables of every method are covered. Any doubt is :unproven.
  class EquivalenceJudge
    def initialize(level:)
      @level = level
      @fingerprint = InstructionSequenceFingerprint.new(level: level)
    end

    def judge(original_source:, mutated_source:, path:)
      original = compile(original_source, path)
      mutated = compile(mutated_source, path)
      return unproven(:compile_failed) unless original && mutated
      return unproven(:reflection) if @level == :relaxed && reflective?(original_source, path)

      same = @fingerprint.call(original) == @fingerprint.call(mutated)
      same ? Verdict.new(status: :proven_equivalent, reason: :identical_instruction_sequences) : unproven(:different)
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

    def unproven(reason)
      Verdict.new(status: :unproven, reason: reason)
    end
  end
end
