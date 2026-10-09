# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # The subjects to mutate: every def in the included files, narrowed by
    # --subject patterns and by --since (methods with a changed line).
    class SubjectSelection
      def initialize(config, diagnostics)
        @config = config
        @diagnostics = diagnostics
        @root = File.realpath(config.root)
      end

      def select(files)
        subjects = find(files)
        subjects = by_pattern(subjects, @config["subjects"]) if @config["subjects"].any?
        subjects = by_change(subjects, @config["since"]) if @config["since"]
        subjects
      end

      # "Klass#meth", "Klass.meth", or a namespace prefix ("Klass", "A::B").
      def self.match?(id, pattern)
        id == pattern || %w[# . ::].any? { |separator| id.start_with?("#{pattern}#{separator}") }
      end

      private

      def find(files)
        finder = SubjectFinder.new
        files.flat_map do |file|
          parsed = finder.call(file)
          parsed.errors.first(1).each do |message|
            @diagnostics.warn("#{file.delete_prefix("#{@root}/")} does not parse: #{message}")
          end
          parsed.subjects
        end
      end

      def by_pattern(subjects, patterns)
        subjects.select { |subject| patterns.any? { |pattern| self.class.match?(subject.id, pattern) } }
      end

      def by_change(subjects, ref)
        changed = Selection::GitDiff.changed_lines(ref, root: @root)
                                    .transform_keys { |file| Selection::CoverageMap.canonical(file) }
        subjects.select do |subject|
          changed[subject.file]&.any? { |line| subject.contains_line?(line) }
        end
      end
    end
  end
end
