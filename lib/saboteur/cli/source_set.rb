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
          "(Rails apps: bundle exec rails generate saboteur:install writes the config; other projects: " \
          "saboteur init) or fix the patterns"
      end
    end
  end
end
