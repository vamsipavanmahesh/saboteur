# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../engine/bytecode_equivalence"
require_relative "../execution/external_runner"
require_relative "../mutation_source/builtin"

module Saboteur
  module Reporter
    # Why a survivor is worth a look, as a LABEL ONLY (#192): the label
    # lands in reports so a reader can sort real gaps from noise. Every
    # label is a HEURISTIC, not a diagnosis - inspect the survivor before
    # acting on it, and never add a test or ignore a mutant from the label
    # alone. Labels never change scores or the exit code.
    #
    # One label per survivor, first match wins:
    #   likely_equivalent - the mutant compiles to the same instructions as
    #     the original (the #151/#169 bytecode filter): strong evidence of
    #     a no-op mutant, worth checking against the source. First: a
    #     no-op mutant's survival says nothing about the suite.
    #   arid         - every line an edit touches matches an arid pattern
    #     (logging and friends, #111/#187). The builtin hint list decides;
    #     a configured arid policy does not change the label.
    #   missing_test - a test covered the line and passed, which MAY mean
    #     the suite reaches the code without pinning this behaviour. The
    #     covering list is only the PLANNED coverage: whole-body (coarse)
    #     mutants carry method-level guesses, so they never get this
    #     label, and neither does anything without real coverage.
    #   tool_limit   - survivors saboteur could not observe faithfully: an
    #     external-runner run records only the pseudo-test id, never real
    #     coverage (#1071). A re-eval refusal records no signal on the
    #     result yet, so that half of the reservation is still unemitted.
    #
    # A survivor with no matching signal stays unlabeled.
    module SurvivorClassification
      LABELS = %w[likely_equivalent arid missing_test tool_limit].freeze

      class << self
        def label(result, arid: MutationSource::Builtin::DEFAULT_ARID)
          return nil unless result.status == :survived
          return "likely_equivalent" if equivalent?(result)
          return "arid" if arid?(result, arid)
          return "tool_limit" if tool_limited?(result)
          return "missing_test" if possible_test_gap?(result)

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

        # An external runner reports one pseudo id for every mutant and no
        # coverage map, so a survivor there was never observed against real
        # tests. Pseudo id next to a real id keeps missing_test (#305).
        def tool_limited?(result)
          result.covered_by.any? && result.covered_by.all? { |id| id == Execution::ExternalRunner::PSEUDO_TEST }
        end

        # covered_by is a PLANNED covering list, not a verdict about what
        # the suite asserts: coarse (whole-body) mutants carry method-level
        # guesses, so they never read as real coverage (#305 QA). No
        # pseudo-id filtering is needed here: tool_limited? runs first and
        # claims every all-pseudo survivor, so a non-empty list at this
        # point always holds a real id (#1100).
        def possible_test_gap?(result)
          !result.mutation.coarse && result.covered_by.any?
        end

        # Arid only when EVERY line an edit touches reads as arid: an edit
        # that starts on a logging line but removes a composite body is not
        # arid. The operator never decides: removing a logging statement is
        # arid whatever removed it.
        def arid?(result, patterns)
          regexps = patterns.map { |pattern| Regexp.new(pattern) }
          tree = Prism.parse(result.subject.file_source)
          result.mutation.edits.all? do |edit|
            lines = edited_lines(result.subject, edit)
            next true if lines.any? && lines.all? { |line| regexps.any? { |regexp| line.strip.match?(regexp) } }

            inside_arid_call?(tree, edit, regexps)
          end
        end

        # Line text misses edits that sit INSIDE an arid call: the lazy log
        # message in a `warn do ... end` block starts with the string, not
        # the logger, so block-form logging never read as arid (#665). Walk
        # the tree instead: an edit is arid when ANY call swallowing it
        # matches a pattern. The edit may sit inside a nested call in the
        # message (the `&.` in `job.source_location&.join` inside the warn
        # block), and the logger call further out still decides. An edit
        # too big for the arid call (the call plus following code) stays
        # unlabeled.
        def inside_arid_call?(tree, edit, regexps)
          return false unless tree.success?

          enclosing_calls(tree.value, edit.start_byte, edit.end_byte).any? do |call|
            regexps.any? { |regexp| regexp.match?(call_head(call)) }
          end
        end

        # The call's identity - receiver, operator and message, without its
        # arguments or block. Matching the whole slice lets an arid-looking
        # SIBLING statement inside the block body swallow an unrelated edit
        # (a tracer.instrument next to the edit marks everything in the
        # block arid, #665 security probe).
        def call_head(call)
          boundary = (call.opening_loc || call.arguments&.arguments&.first || call.block)&.start_offset
          call.slice[0, (boundary || call.end_offset) - call.start_offset].rstrip
        end

        # Every CallNode swallowing [from, to], outermost first.
        def enclosing_calls(node, from, to, found = [])
          return found unless node.start_offset <= from && to <= node.end_offset

          found << node if node.is_a?(Prism::CallNode)
          node.child_nodes.each { |child| enclosing_calls(child, from, to, found) if child }
          found
        end

        # Edit offsets are BYTES, so the line lookup runs on the binary
        # view (index/rindex are byte-exact there) and only the extracted
        # lines are decoded, scrubbed so a partial multibyte sequence at an
        # edit boundary cannot raise on the pattern match.
        def edited_lines(subject, edit)
          bytes = subject.file_source.b
          last = [edit.end_byte - 1, edit.start_byte].max
          line_start = (bytes.byteslice(0, edit.start_byte).rindex("\n") || -1) + 1
          line_end = bytes.index("\n", last) || bytes.bytesize
          bytes.byteslice(line_start, line_end - line_start).force_encoding(Encoding::UTF_8).scrub.lines
        end
      end
    end
  end
end
