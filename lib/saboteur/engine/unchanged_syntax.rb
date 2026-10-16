# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require_relative "../inline_suppression"
require_relative "../constant_subject_finder"

module Saboteur
  class Engine
    # Tells whether a method still has, in the working tree, the syntax it had
    # at the merge base of the --since ref. A change to a comment, a blank
    # line or spacing leaves it the same, so no mutant of it asks a question
    # the change raised. Comparison is of the Prism tree without locations
    # and comments, plus the frozen_string_literal magic comment and the
    # `sig` in front of the def, which both change what runs. `__LINE__` is
    # the one node whose value is its location, so it keeps its line: a
    # method that moved, or one with a line added above its `__LINE__`, is
    # not the same.
    #
    # Anything that cannot be compared says the method changed: a file or
    # method that is new at the base, a base that does not parse, a method
    # name defined twice in a file.
    class UnchangedSyntax
      def initialize(base, root:)
        @base = base
        @root = root
        @base_subjects = {}
        @current_subjects = {}
      end

      def unchanged?(subject)
        before = base_subject(subject)
        return false unless before

        return false unless suppression_signature(before) == suppression_signature(subject)

        before.frozen_literals == subject.frozen_literals && before.sig_source == subject.sig_source &&
          self.class.digest(before.node) == self.class.digest(subject.node)
      end

      # The node as plain data: type and fields, never locations (except
      # the line a `__LINE__` stands for).
      def self.digest(value)
        case value
        when Prism::SourceLineNode then [value.type, value.location.start_line]
        when Prism::Node
          fields = value.deconstruct_keys(nil).except(:node_id)
          [value.type, fields.transform_values { |field| digest(field) }]
        when Array then value.map { |item| digest(item) }
        when Prism::Location then nil
        else value
        end
      end

      private

      def suppression_signature(subject)
        InlineSuppression.new(subject.file, subject.file_source).signature(subject)
      end

      def base_subject(subject)
        return nil unless current_subjects(subject).key?(subject.id)

        base_subjects(subject.file)[subject.id]
      end

      # Only the names defined once: with two defs of a name, which one a
      # change belongs to is a guess. Constant literal subjects compare the
      # same way (#306): a comment-only change to the literal prunes them.
      def unique_by_id(source, file)
        subjects = SubjectFinder.new.call(file, source: source).subjects +
                   ConstantSubjectFinder.new.call(file, source: source).subjects
        counts = subjects.map(&:id).tally
        subjects.select { |subject| counts[subject.id] == 1 }.to_h { |subject| [subject.id, subject] }
      end

      def current_subjects(subject)
        file = subject.file
        @current_subjects.fetch(file) { @current_subjects[file] = unique_by_id(subject.file_source, file) }
      end

      def base_subjects(file)
        @base_subjects.fetch(file) do
          text = Selection::GitDiff.file_at(@base, file.delete_prefix("#{@root}/"), root: @root)
          @base_subjects[file] = text ? unique_by_id(text, file) : {}
        end
      end
    end
  end
end
