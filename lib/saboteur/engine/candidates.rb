# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"

module Saboteur
  class Engine
    # Builds the mutation sources from config and turns their proposals for
    # a subject into runnable candidates: applied, re-parsed, de-duplicated,
    # coarse first. Returns [[mutation, mutated_text]].
    class Candidates
      def self.build_sources(config)
        root = File.realpath(config.root)
        config["sources"].map do |entry|
          next MutationSource::Builtin.new(arid: config["arid"]) if entry == "builtin"

          file, const = entry.split(":", 2)
          raise ConfigError, "mutation source #{entry.inspect} must be builtin or path.rb:ClassName" unless const

          require File.expand_path(file, root)
          Object.const_get(const).new
        end
      end

      def initialize(sources, diagnostics)
        @sources = sources
        @diagnostics = diagnostics
      end

      def for(subject)
        unless parses?(subject.source)
          @diagnostics.record_generation(subject, source: "subject", reason: "invalid_subject_syntax")
          return []
        end

        seen = Set[subject.source]
        list = @sources.flat_map { |source| proposals(source, subject) }.filter_map do |mutation|
          candidate(subject, mutation, seen)
        end
        list.sort_by.with_index { |(mutation, _), index| [mutation.coarse ? 0 : 1, index] }
      end

      private

      def proposals(source, subject)
        proposals = source.mutations_for(subject)
        if proposals.empty?
          @diagnostics.record_generation(subject, source: source_name(source), reason: "empty_generation")
        end
        proposals
      end

      def source_name(source)
        name = source.name if source.respond_to?(:name)
        name || "anonymous"
      end

      def record_drop(subject, mutation, reason)
        @diagnostics.record_generation(subject, source: mutation.source, operator: mutation.operator, reason: reason)
        nil
      end

      def candidate(subject, mutation, seen)
        text = subject.apply(mutation.edits)
        return record_drop(subject, mutation, "unchanged") if text == subject.source
        return record_drop(subject, mutation, "duplicate") if seen.include?(text)

        seen << text
        unless parses?(text)
          @diagnostics.count_invalid_mutation
          return record_drop(subject, mutation, "invalid_syntax")
        end

        [mutation, text]
      rescue ArgumentError => e
        @diagnostics.warn("#{subject.id}: dropped #{mutation.source} mutation: #{e.message}")
        record_drop(subject, mutation, "invalid_edit")
      end

      def parses?(text)
        Prism.parse(text).success?
      end
    end
  end
end
