# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # The warning shown before a run on a tree with uncommitted changes
  # (#309, #316). Mutants run your code and can change the tree, so the
  # warning stays; it splits the raw count so a tree full of notes or trial
  # setup files does not read like application edits about to be mutated.
  #
  # Each change lands in exactly one group, so the groups add up to the
  # count: saboteur setup files first (the config file the run reads, a
  # trial Gemfile and its lock), then the mutation scope (a Ruby path that
  # an include pattern matches and no exclude pattern does), then the rest.
  # Paths are matched against the patterns, not looked up on disk, so a
  # deleted source still counts as inside the scope. The scope is the
  # configured one: --since, --subject and source operands narrow a run
  # further, after this warning.
  class DirtyTreeWarning
    SHOWN_PATHS = 5
    MATCH_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB
    ADVICE = "Mutants run your code and could alter or delete files; " \
             "run on a clean, committed tree or a CI checkout."

    def self.for(state, config, config_path:, gemfile:)
      new(state, include: config["include"], exclude: config["exclude"],
                 setup_files: setup_files(config.root, config_path: config_path, gemfile: gemfile))
    end

    # Files a trial of saboteur adds, relative to the root: the config file
    # the run reads and, when BUNDLE_GEMFILE names a Gemfile other than the
    # root's own, that Gemfile and its lock.
    def self.setup_files(root, config_path:, gemfile:)
      files = [File.expand_path(config_path || Config::FILE, root)]
      if gemfile && File.expand_path(gemfile, root) != File.join(root, "Gemfile")
        files.push(File.expand_path(gemfile, root), "#{File.expand_path(gemfile, root)}.lock")
      end
      prefix = File.join(root, "")
      files.select { |file| file.start_with?(prefix) }.map { |file| file.delete_prefix(prefix) }
    end

    def initialize(state, include:, exclude:, setup_files:)
      @state = state
      @include = include
      @exclude = exclude
      @setup_files = setup_files
    end

    def to_s
      return unless @state.dirty

      setup, rest = @state.changes.partition { |change| @setup_files.include?(change.path) }
      scope, outside = rest.partition { |change| in_scope?(change.path) }
      [summary(setup, scope, outside), named("inside the mutation scope", scope), named("setup files", setup),
       "  #{ADVICE}"].compact.join("\n")
    end

    private

    def summary(setup, scope, outside)
      groups = [scope.empty? ? "none inside the mutation scope" : counted("inside the mutation scope", scope),
                counted("outside it", outside)]
      groups << counted("saboteur setup file(s)", setup) unless setup.empty?
      "saboteur: warning: #{@state.changed_files} uncommitted change(s) in the working tree: #{groups.join(', ')}."
    end

    def counted(label, changes)
      tracked = changes.count(&:tracked)
      "#{changes.size} #{label} (#{tracked} tracked, #{changes.size - tracked} untracked)"
    end

    def named(label, changes)
      return if changes.empty?

      paths = changes.first(SHOWN_PATHS).map(&:path).join(", ")
      more = changes.size - SHOWN_PATHS
      "  #{label}: #{paths}#{" and #{more} more" if more.positive?}"
    end

    def in_scope?(path)
      path.end_with?(".rb") && matches?(@include, path) && !matches?(@exclude, path)
    end

    def matches?(patterns, path)
      patterns.any? { |pattern| File.fnmatch?(pattern, path, MATCH_FLAGS) }
    end
  end
end
