# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # The original and replacement text of one mutant, and the line it
    # changes, for compact one-line output.
    module MutationText
      module_function

      def line(result)
        result.subject.line_of(sorted_edits(result).first.start_byte)
      end

      def original(result)
        join(result) { |edit| result.subject.file_source.byteslice(edit.start_byte, edit.end_byte - edit.start_byte) }
      end

      def replacement(result)
        join(result, &:replacement)
      end

      def sorted_edits(result)
        result.mutation.edits.sort_by(&:start_byte)
      end

      # Whole-body mutants carry a long text; one line keeps the output compact.
      def join(result, &pick)
        text = sorted_edits(result).map { |edit| pick.call(edit).to_s.dup.force_encoding(Encoding::UTF_8).scrub }
                                   .join(" | ")
        flat = text.gsub(/\s*\n\s*/, " ").strip
        flat.length > 60 ? "#{flat[0, 57]}..." : flat
      end
    end
  end
end
