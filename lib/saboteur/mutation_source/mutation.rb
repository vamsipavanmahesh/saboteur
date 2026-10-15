# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"

module Saboteur
  module MutationSource
    # One candidate change to one subject. subject_id is "Klass#meth" or "Klass.meth".
    # coarse: true for whole-body replacements, which run before fine-grained ones.
    Mutation = Data.define(:subject_id, :operator, :edits, :coarse, :source) do
      def initialize(subject_id:, operator:, edits:, coarse: false, source: "builtin")
        raise ArgumentError, "a mutation needs at least one edit" if edits.empty?

        super(subject_id:, operator:, edits: edits.freeze, coarse:, source:)
      end

      # Stable id for the ignore list. Offsets are made relative to subject_start
      # so edits elsewhere in the file do not change the id. The digest hashes
      # bytes, not encodings: a binary-read source and a UTF-8 replacement hold
      # the same identity, and joining them without .b raises under LANG=C.
      def digest(subject_start:, original_source:)
        parts = edits.map do |edit|
          original = original_source.byteslice(edit.start_byte, edit.end_byte - edit.start_byte)
          [edit.start_byte - subject_start, original.to_s.b, edit.replacement.b].join("\0".b)
        end
        Digest::SHA256.hexdigest([subject_id.to_s.b, operator.to_s.b, *parts].join("\x1F".b))[0, 16]
      end
    end
  end
end
