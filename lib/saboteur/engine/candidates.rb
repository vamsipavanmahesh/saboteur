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
        return [] unless parses?(subject.source)

        seen = Set[subject.source]
        list = @sources.flat_map { |source| source.mutations_for(subject) }.filter_map do |mutation|
          candidate(subject, mutation, seen)
        end
        list.sort_by.with_index { |(mutation, _), index| [mutation.coarse ? 0 : 1, index] }
      end

      private

      def candidate(subject, mutation, seen)
        text = subject.apply(mutation.edits)
        return if seen.include?(text)

        seen << text
        unless parses?(text)
          @diagnostics.count_invalid_mutation
          return
        end

        [mutation, text]
      rescue ArgumentError => e
        @diagnostics.warn("#{subject.id}: dropped #{mutation.source} mutation: #{e.message}")
        nil
      end

      def parses?(text)
        Prism.parse(text).success?
      end
    end
  end
end
