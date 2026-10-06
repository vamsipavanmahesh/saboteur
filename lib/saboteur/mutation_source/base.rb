# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"

module Saboteur
  module MutationSource
    # A replacement of source bytes [start_byte, end_byte) in file with text.
    # Offsets are byte offsets into the file as read from disk (UTF-8),
    # matching Prism::Location#start_offset / #end_offset.
    Edit = Data.define(:file, :start_byte, :end_byte, :replacement) do
      def initialize(file:, start_byte:, end_byte:, replacement:)
        raise ArgumentError, "start_byte must be >= 0" if start_byte.negative?
        raise ArgumentError, "end_byte must be >= start_byte" if end_byte < start_byte

        super
      end
    end

    # One candidate change to one subject. subject_id is "Klass#meth" or "Klass.meth".
    # coarse: true for whole-body replacements, which run before fine-grained ones.
    Mutation = Data.define(:subject_id, :operator, :edits, :coarse, :source) do
      def initialize(subject_id:, operator:, edits:, coarse: false, source: "builtin")
        raise ArgumentError, "a mutation needs at least one edit" if edits.empty?

        super(subject_id:, operator:, edits: edits.freeze, coarse:, source:)
      end

      # Stable id for the ignore list. Offsets are made relative to subject_start
      # so edits elsewhere in the file do not change the id.
      def digest(subject_start:, original_source:)
        parts = edits.map do |edit|
          original = original_source.byteslice(edit.start_byte, edit.end_byte - edit.start_byte)
          [edit.start_byte - subject_start, original, edit.replacement].join("\0")
        end
        Digest::SHA256.hexdigest([subject_id, operator, *parts].join("\x1F"))[0, 16]
      end
    end

    # Extension point. A source yields Mutation objects for a subject.
    # Built-in operators are one source; external sources (for example a
    # service that proposes edits) implement the same method and are
    # registered in config. Every edit must lie inside the subject's byte range.
    class Base
      def name
        self.class.name
      end

      # subject responds to #id, #file, #start_byte, #end_byte, #source.
      def mutations_for(_subject)
        raise NotImplementedError, "#{self.class} must implement #mutations_for"
      end
    end
  end
end
