# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # The effective source set a run will mutate, refused when it is empty.
    module SourceSet
      private

      # The Rails-shaped footgun (#447): the default include targets plain
      # gems, so a first run on an app/ tree selects nothing and would exit 0
      # over 0 subjects - a green gate that mutates nothing, every CI run.
      # Refuse like a typo'd source: exit 2, name the stale pattern and the
      # way out. --dry-run still previews: it gates nothing.
      def refuse_empty_source_set
        return unless config.included_files.empty?

        raise UsageError, empty_source_set_message
      end

      # A --since ref whose resolved range diffs empty yields 0 subjects
      # and a green run over nothing: `saboteur pr <merge_sha>` on a
      # checkout AT the merge diffs the merge against itself (#643).
      # Refuse like a typo'd ref: exit 2, name the base and the range.
      def refuse_empty_since_range
        ref = config["since"]
        return unless ref

        paths = Selection::GitDiff.changed_paths(ref, root: config.root)
        return unless paths.values.all?(&:empty?)

        base = Selection::GitDiff.merge_base(ref, root: config.root)
        raise UsageError, "--since #{ref}: the resolved range #{base}..the working tree has no changes - " \
                          "the run would pass with 0 subjects. A checkout AT the ref (the CI merge-sha " \
                          "checkout) diffs it against itself: fetch the merge's parent, or point --since " \
                          "at the base of the change under test"
      end

      def empty_source_set_message
        include_patterns = config["include"]
        matched = include_patterns.flat_map { |pattern| Dir.glob(pattern, base: config.root) }
                                  .select { |file| file.end_with?(".rb") }
        cause = if matched.empty?
                  "include: #{include_patterns.join(', ')} selects no Ruby file"
                else
                  "exclude: #{config['exclude'].join(', ')} removes every included file"
                end
        "#{cause} - the run would pass with 0 subjects. Point include at your code " \
          "(Rails apps: bundle exec rails generate saboteur:install writes the config) or fix the patterns"
      end
    end
  end
end
