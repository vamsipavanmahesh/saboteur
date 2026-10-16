# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "../inline_suppression"

module Saboteur
  class Engine
    # Builds the mutation sources from config and turns their proposals for
    # a subject into runnable candidates: applied, re-parsed, de-duplicated,
    # coarse first. Returns [[mutation, mutated_text]].
    class Candidates
      def self.build_sources(config)
        root = File.realpath(config.root)
        config["sources"].map do |entry|
          if entry == "builtin"
            next MutationSource::Builtin.new(arid: config["arid"], operators: config["operators"],
                                             exclude_operators: config["exclude_operators"])
          end

          file, const = entry.split(":", 2)
          raise ConfigError, "mutation source #{entry.inspect} must be builtin or path.rb:ClassName" unless const

          require File.expand_path(file, root)
          Object.const_get(const).new
        end
      end

      def initialize(sources, diagnostics, hazard_guard: nil, bytecode: BytecodeEquivalence.new)
        @sources = sources
        @diagnostics = diagnostics
        @hazard_guard = hazard_guard
        @bytecode = bytecode
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
        list = suppress_inline(list, subject)
        list = suppress_hazards(list, subject)
        list.sort_by.with_index { |(mutation, _), index| [mutation.coarse ? 0 : 1, index] }
      end

      private

      def suppress_inline(list, subject)
        directives = InlineSuppression.new(subject.file, subject.file_source)
        list.reject do |mutation, _text|
          directive = directives.reason(subject, mutation)
          @diagnostics.record_inline_suppression(subject, mutation, directive) if directive
          directive
        end
      end

      # The hazard guard (issue #102) refuses mutants that would leave a
      # destructive call running with altered inputs; each refusal is counted.
      def suppress_hazards(list, subject)
        return list unless @hazard_guard

        kept, suppressed = @hazard_guard.partition(list, subject)
        suppressed.each { |(mutation, _)| @diagnostics.record_hazard_suppression(subject, mutation) }
        kept
      end

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
          @diagnostics.warn("#{subject.id}: dropped #{mutation.operator} mutation (did not parse)")
          return record_drop(subject, mutation, "invalid_syntax")
        end

        return record_drop(subject, mutation, "equivalent_bytecode") if equivalent?(subject, text)

        [mutation, text]
      rescue ArgumentError => e
        @diagnostics.warn("#{subject.id}: dropped #{mutation.source} mutation: #{e.message}")
        record_drop(subject, mutation, "invalid_edit")
      end

      def equivalent?(subject, text)
        @bytecode.equivalent?(subject.source, text, frozen_string_literal: subject.frozen_literals)
      end

      def parses?(text)
        Prism.parse(text).success?
      end
    end
  end
end
