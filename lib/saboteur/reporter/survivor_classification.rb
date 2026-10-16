# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../engine/bytecode_equivalence"
require_relative "../mutation_source/builtin"

module Saboteur
  module Reporter
    # Why a survivor is worth a look, as a LABEL ONLY (#192): the label
    # lands in reports so a reader can sort real gaps from noise; it never
    # changes scores or the exit code (that is a separate decision).
    #
    # One label per survivor, first match wins:
    #   likely_equivalent - the mutant compiles to the same instructions as
    #     the original (the #151/#169 bytecode filter), so no test can kill
    #     it. First: a no-op mutant's survival says nothing about the suite.
    #   arid         - the mutated line matches an arid pattern (logging and
    #     friends, #111/#187), so the statement is unlikely to be worth an
    #     assertion.
    #   missing_test - a test covered the line and passed: the suite reaches
    #     the code but asserts too little.
    #   tool_limit   - reserved for survivors saboteur could not observe
    #     faithfully (re-eval refusal, external runner without coverage). No
    #     result records that signal yet, so the label is never emitted.
    #
    # A survivor with no matching signal stays unlabeled.
    module SurvivorClassification
      LABELS = %w[likely_equivalent arid missing_test tool_limit].freeze

      class << self
        def label(result, arid: MutationSource::Builtin::DEFAULT_ARID)
          return nil unless result.status == :survived
          return "likely_equivalent" if equivalent?(result)
          return "arid" if arid?(result, arid)
          return "missing_test" if result.covered_by.any?

          nil
        end

        private

        # The mutant's own def text, compiled side by side with the
        # original: equal instruction sequences mean behaviour cannot
        # change. Edits index the whole file, so they shift by the def's
        # start byte before splicing into the def text.
        def equivalent?(result)
          subject = result.subject
          original = subject.source
          mutated = result.mutation.edits.sort_by(&:start_byte).reverse.inject(original) do |text, edit|
            from = edit.start_byte - subject.start_byte
            to = edit.end_byte - subject.start_byte
            text.byteslice(0, from) + edit.replacement + text.byteslice(to..)
          end
          Engine::BytecodeEquivalence.new.equivalent?(original, mutated,
                                                      frozen_string_literal: subject.frozen_literals)
        end

        # The line holding an edit decides, not the operator: removing a
        # logging statement is arid whatever removed it.
        def arid?(result, patterns)
          lines = result.mutation.edits.map { |edit| edited_line(result.subject, edit) }
          lines.any? do |line|
            patterns.any? { |pattern| line.strip.match?(Regexp.new(pattern)) }
          end
        end

        def edited_line(subject, edit)
          source = subject.file_source
          line_start = (source.byteslice(0, edit.start_byte).rindex("\n") || -1) + 1
          line_end = source.index("\n", edit.start_byte) || source.bytesize
          source.byteslice(line_start...line_end).force_encoding(Encoding::UTF_8)
        end
      end
    end
  end
end
