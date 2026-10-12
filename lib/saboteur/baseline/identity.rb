# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

module Saboteur
  module Baseline
    # Stable mutation identity, separate from the bytes accepted by a reviewer.
    class Identity
      VERSION = 1

      attr_reader :tuple, :id, :context

      def initialize(subject:, mutation:, root:)
        @subject = subject
        @mutation = mutation
        raise ConfigError, "baseline mutation subject differs from its subject" unless mutation.subject_id == subject.id

        file = Pathname.new(self.class.canonical_path(subject.file))
        base = Pathname.new(self.class.canonical_path(root))
        path = file.relative_path_from(base).to_s
        raise ConfigError, "baseline subject outside project root" if path == ".." || path.start_with?("../")

        @tuple = immutable([VERSION, path, subject.id, mutation.source, mutation.operator, mutation.coarse, edits])
        @id = Digest::SHA256.hexdigest(JSON.generate(tuple)).freeze
        @context = Digest::SHA256.hexdigest(subject.source.b).freeze
      end

      # Resolve existing ancestors too, so a missing evidence path under a
      # symlinked checkout has the same root identity as an existing subject.
      def self.canonical_path(path)
        expanded = File.expand_path(path)
        return File.realpath(expanded) if File.exist?(expanded)

        parent = File.dirname(expanded)
        File.join(canonical_path(parent), File.basename(expanded))
      end

      def entry
        { "id" => id, "identity" => tuple, "context" => context }
      end

      private

      def immutable(value)
        case value
        when Array then value.map { |entry| immutable(entry) }.freeze
        when String then value.dup.freeze
        else value
        end
      end

      def edits
        previous_end = nil
        @mutation.edits.sort_by { |edit| [edit.start_byte, edit.end_byte] }.map do |edit|
          validate_edit(edit, previous_end)
          previous_end = edit.end_byte
          original = @subject.file_source.byteslice(edit.start_byte, edit.end_byte - edit.start_byte)
          [edit.start_byte - @subject.start_byte, edit.end_byte - @subject.start_byte,
           original.b.unpack1("H*"), edit.replacement.b.unpack1("H*")]
        end
      end

      def validate_edit(edit, previous_end)
        unless self.class.canonical_path(edit.file) == self.class.canonical_path(@subject.file) &&
               edit.start_byte >= @subject.start_byte && edit.end_byte <= @subject.end_byte &&
               edit.end_byte >= edit.start_byte
          raise ConfigError, "baseline edit outside subject or in another file"
        end
        return unless previous_end && edit.start_byte < previous_end

        raise ConfigError, "baseline edits overlap"
      end
    end
  end
end
