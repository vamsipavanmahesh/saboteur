# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # The subjects to mutate: every def in the included files, narrowed by
    # --subject patterns and by --since (methods with a changed line).
    class SubjectSelection
      # Lines changed since the --since ref, by file; nil without --since.
      attr_reader :changed_lines

      def initialize(config, diagnostics)
        @config = config
        @diagnostics = diagnostics
        @root = File.realpath(config.root)
        @changed_lines = nil
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
          InlineSuppression.new(file, File.read(file))
          parsed = finder.call(file)
          @diagnostics.record_discovery_failure(file, reason: "invalid_file_syntax") unless parsed.errors.empty?
          parsed.errors.first(1).each do |message|
            @diagnostics.warn("#{file.delete_prefix("#{@root}/")} does not parse: #{message}")
          end
          parsed.subjects
        end
      end

      def by_pattern(subjects, patterns)
        patterns.each do |pattern|
          next if subjects.any? { |subject| self.class.match?(subject.id, pattern) }

          @diagnostics.warn("--subject #{pattern} matches no subject (patterns are names like " \
                            "Klass, Klass#meth or Klass.meth, not globs)")
        end
        subjects.select { |subject| patterns.any? { |pattern| self.class.match?(subject.id, pattern) } }
      end

      def by_change(subjects, ref)
        @changed_lines = Selection::GitDiff.changed_lines(ref, root: @root)
                                           .transform_keys { |file| Selection::CoverageMap.canonical(file) }
        changed = subjects.select do |subject|
          @changed_lines[subject.file]&.any? { |line| subject.contains_line?(line) }
        end
        drop_unchanged_syntax(changed, ref)
      end

      # A method whose only changes are comments, blank lines or spacing has
      # nothing new to test.
      def drop_unchanged_syntax(subjects, ref)
        return subjects if subjects.empty?

        comparison = UnchangedSyntax.new(Selection::GitDiff.merge_base(ref, root: @root), root: @root)
        same, kept = subjects.partition { |subject| comparison.unchanged?(subject) }
        report_unchanged_syntax(same)
        kept
      end

      def report_unchanged_syntax(subjects)
        return if subjects.empty?

        names = subjects.first(5).map(&:id).join(", ")
        more = subjects.size > 5 ? ", ..." : ""
        @diagnostics.inform("#{subjects.size} changed method(s) differ only in comments or formatting, " \
                            "so they are skipped: #{names}#{more}")
      end
    end
  end
end
