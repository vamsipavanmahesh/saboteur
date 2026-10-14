# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # --guess-tests: the specs that sit next to the changed source files by
    # naming convention (lib/a/b.rb -> spec/a/b_spec.rb). A guess, not a
    # coverage fact: a spec that only reaches the file through another one
    # is not found. Packwerk packs (a directory with a package.yml) map to the
    # spec directory inside the same pack, and controllers also map to request
    # specs. Only files whose changed lines carry a mutation subject need a
    # guessed spec; when some of those have none, the run narrows to the
    # specs it found and warns.
    class TestGuess
      Result = Data.define(:specs, :unmatched, :subjectless, :changed)

      SOURCE_ROOTS = %w[lib app].freeze

      def initialize(config)
        @root = File.realpath(config.root)
        @config = config
      end

      # specs: existing spec files (relative paths); unmatched: changed
      # source files with a mutation subject on their changed lines but no
      # guessed spec; subjectless: changed files whose changed lines carry
      # no mutation subject, so they need no spec; changed: how many source
      # files changed.
      def call
        lines_by_file = changed_lines_by_file
        guesses = lines_by_file.keys.to_h { |file| [file, guess_for(file)] }
        subjectless = subjectless_files(lines_by_file)
        Result.new(specs: guesses.values.compact.uniq.sort,
                   unmatched: guesses.except(*subjectless).select { |_, spec| spec.nil? }.keys,
                   subjectless: subjectless,
                   changed: lines_by_file.size)
      end

      private

      # Changed files that saboteur would mutate, relative to the root, with
      # their changed line numbers.
      def changed_lines_by_file
        included = @config.included_files.to_set
        Selection::GitDiff.changed_lines(@config["since"], root: @root)
                          .each_with_object({}) do |(file, lines), map|
          canonical = Selection::CoverageMap.canonical(file)
          map[canonical.delete_prefix("#{@root}/")] = lines if included.include?(canonical)
        end.sort.to_h
      end

      # Changed files whose changed lines carry no mutation subject: the run
      # mutates nothing in them, so they cannot require a spec. Mirrors the
      # run's subject selection, including its comment/formatting-only skip:
      # a deletion whose remaining context lines are blank or comments, or a
      # comment-only change inside a method, leaves the file subjectless.
      def subjectless_files(lines_by_file)
        return [] if lines_by_file.empty?

        comparison = UnchangedSyntax.new(Selection::GitDiff.merge_base(@config["since"], root: @root), root: @root)
        finder = SubjectFinder.new
        lines_by_file.reject do |file, lines|
          subjects = finder.call(File.join(@root, file)).subjects
          subjects.select { |subject| lines.any? { |line| subject.contains_line?(line) } }
                  .any? { |subject| !comparison.unchanged?(subject) }
        end.keys
      end

      def guess_for(file)
        candidates_for(file).find { |path| File.file?(File.join(@root, path)) }
      end

      # Candidate specs for a source file, most specific first: the nearest
      # package.yml pack's own spec directory, then the app-wide one.
      def candidates_for(file)
        pack = pack_of(file)
        # pack is nil for files outside packs: "#{nil}/" is "/", which
        # never prefixes a relative path, so delete_prefix is a no-op there.
        base = file.delete_prefix("#{pack}/")
        spec_root = pack ? "#{pack}/spec" : "spec"
        stem = base.delete_suffix(".rb")
        rest = stem.split("/", 2)
        rooted = rest.size == 2 && SOURCE_ROOTS.include?(rest.first)
        names = rooted ? [rest.last, "lib/#{rest.last}", stem] : [stem]
        names = names.flat_map { |name| [name, *request_names(name)] }.uniq
        names.map { |name| "#{spec_root}/#{name}_spec.rb" }
      end

      # Rails tests controllers as request specs: spec/requests/users_spec.rb
      # or spec/requests/users_controller_spec.rb for controllers/users_controller.rb.
      def request_names(name)
        return [] unless name.start_with?("controllers/")

        path = name.delete_prefix("controllers/")
        ["requests/#{path}", "requests/#{path.delete_suffix('_controller')}"].uniq
      end

      # The nearest ancestor directory holding a package.yml (a packwerk
      # pack), relative to the root. The root itself is not a pack here:
      # its specs follow the plain mapping.
      def pack_of(file)
        dir = File.dirname(file)
        until dir == "."
          return dir if pack_dirs.include?(dir)

          dir = File.dirname(dir)
        end
      end

      def pack_dirs
        @pack_dirs ||= Dir.glob("**/package.yml", base: @root).to_set { |path| File.dirname(path) }
      end
    end
  end
end
