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
  # trial Gemfile and its lock), then the mutation scope (a file the run's
  # include and exclude select, the way Config#included_files does), then
  # the rest. A path the patterns match also counts, so a deleted source is
  # still inside the scope. The scope is the run's include and exclude:
  # source operands replace them, and --since and --subject narrow a run
  # further, after this warning.
  class DirtyTreeWarning
    SHOWN_PATHS = 5
    MATCH_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB
    ADVICE = "Mutants run your code and could alter or delete files; " \
             "run on a clean, committed tree or a CI checkout."

    # The warning text for the run's working tree, or nil on a clean or
    # unknown tree.
    def self.for(config, config_path:, gemfile: ENV.fetch("BUNDLE_GEMFILE", nil))
      state = WorkingTree.new(config.root, ignored: config.output_paths).state
      root = File.realpath(config.root)
      new(state, included: relative(config.included_files, root),
                 include: patterns(config["include"], root), exclude: patterns(config["exclude"], root),
                 setup_files: setup_files(root, config_path: config_path, gemfile: gemfile)).to_s
    end

    # Files a trial of saboteur adds, relative to the root: the config file
    # the run reads and, when BUNDLE_GEMFILE names a Gemfile other than the
    # root's own, that Gemfile and its lock.
    # root is physical (realpath), and so is each file before the compare,
    # so a /var spelling of a /private/var root still matches (#503).
    def self.setup_files(root, config_path:, gemfile:)
      files = [physical(File.expand_path(config_path || Config::FILE, root))]
      trial = gemfile && physical(File.expand_path(gemfile, root))
      files.push(trial, "#{trial}.lock") if trial && trial != File.join(root, "Gemfile")
      relative(files, root)
    end

    # The path with its directory resolved, so a file that does not exist
    # yet still gets the physical spelling of where it would be.
    def self.physical(path)
      File.join(File.realpath(File.dirname(path)), File.basename(path))
    rescue SystemCallError
      path
    end

    # A file outside the root keeps its absolute path, which no
    # root-relative git path can equal.
    def self.relative(files, root)
      prefix = File.join(root, "")
      files.map { |file| file.delete_prefix(prefix) }
    end

    # Patterns as paths relative to the root, so ./lib/**/*.rb and an
    # absolute pattern under the root match the paths git reports.
    def self.patterns(patterns, root)
      patterns.map { |pattern| File.expand_path(pattern, root).delete_prefix(File.join(root, "")) }
    end

    private_class_method :physical, :relative, :patterns

    def initialize(state, included:, include:, exclude:, setup_files:)
      @state = state
      @included = included.to_set
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
      @included.include?(path) || (path.end_with?(".rb") && matches?(@include, path) && !matches?(@exclude, path))
    end

    def matches?(patterns, path)
      patterns.any? { |pattern| File.fnmatch?(pattern, path, MATCH_FLAGS) }
    end
  end
end
