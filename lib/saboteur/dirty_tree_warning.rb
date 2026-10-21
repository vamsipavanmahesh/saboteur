# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # The warning shown before a run on a tree with uncommitted
  # changes (#309, #316); the headline says uncommitted or untracked, so a
  # tree of only scratch files is not read as edits (#604). Mutants run your code and can change the tree, so the
  # warning stays; it splits the raw count so a tree full of notes or trial
  # setup files does not read like application edits about to be mutated.
  #
  # Each change lands in exactly one group, so the groups add up to the
  # count: saboteur setup files first (the config file the run reads, a
  # trial Gemfile and its lock), then the mutation scope (a file the
  # configured include and exclude select, the way Config#included_files
  # does), then the rest. A path the patterns match also counts, so a
  # deleted source is still inside the scope. The scope is the configured
  # one: --since, --subject and source operands narrow a run further, after
  # this warning.
  class DirtyTreeWarning
    SHOWN_PATHS = 5
    MATCH_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB
    ADVICE = "Fix: commit or stash your changes first, or run on a CI checkout - " \
             "mutants run your code and could alter or delete files."

    # The warning text for the run's working tree, or nil on a clean or
    # unknown tree. The root is physical (realpath), like the paths
    # Config#included_files returns.
    def self.for(config, config_path:, gemfile: ENV.fetch("BUNDLE_GEMFILE", nil))
      state = WorkingTree.new(config.root, ignored: config.ignored_tree_paths(gemfile: gemfile)).state
      root = File.realpath(config.root)
      new(state, included: relative(config.included_files, root), include: config["include"],
                 exclude: config["exclude"], root: root,
                 setup_files: setup_files(root, config_path: config_path, gemfile: gemfile)).to_s
    end

    # Files a trial of saboteur adds, relative to the root: the config file
    # the run reads and, when BUNDLE_GEMFILE names a Gemfile other than the
    # root's own, that Gemfile and its lock. Each file is compared by its
    # physical path, so a /var spelling of a /private/var root still
    # matches (#503).
    def self.setup_files(root, config_path:, gemfile:)
      files = [physical(File.expand_path(config_path || Config::FILE, root))]
      trial = gemfile && physical(File.expand_path(gemfile, root))
      files.push(trial, lockfile_for(trial)) if trial && trial != File.join(root, "Gemfile")
      relative(files, root)
    end

    # Bundler's own rule, the same one preflight's execution inputs check
    # against Bundler.default_lockfile: a gems.rb trial locks to gems.locked
    # next to it; every other name gets ".lock" appended.
    def self.lockfile_for(gemfile)
      return File.join(File.dirname(gemfile), "gems.locked") if File.basename(gemfile) == "gems.rb"

      "#{gemfile}.lock"
    end

    # git status paths are relative to the root, so the patterns are too:
    # Dir.glob accepts a leading ./ or an absolute path under the root and
    # File.fnmatch? does not (#503). A pattern outside the root stays
    # absolute and matches no git path.
    def self.relative_patterns(patterns, root)
      patterns.map { |pattern| File.expand_path(pattern, root).delete_prefix(File.join(root, "")) }
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

    private_class_method :physical, :relative

    def initialize(state, included:, include:, exclude:, setup_files:, root:)
      @state = state
      @included = included.to_set
      @include = self.class.relative_patterns(include, root)
      @exclude = self.class.relative_patterns(exclude, root)
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
      "saboteur: warning: #{@state.changed_files} uncommitted or untracked change(s) in the working tree: " \
        "#{groups.join(', ')}."
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
