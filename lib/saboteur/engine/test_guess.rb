# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "pathname"

module Saboteur
  class Engine
    # The specs that sit next to the mutated source files by
    # naming convention (lib/a/b.rb -> spec/a/b_spec.rb). A guess, not a
    # coverage fact: a spec that only reaches the file through another one
    # is not found. Packwerk packs (a directory with a package.yml) map to the
    # spec directory inside the same pack, and controllers also map to request
    # specs. With --since, only files whose changed lines carry a mutation
    # subject need a guessed spec; without --since, every included file with
    # a mutation subject needs one. A file that needs a spec and has none
    # stops the run before boot.
    class TestGuess
      # hints: unmatched file -> its conventional spec path (which does
      # not exist; that is why the file is unmatched), for the stop-before-boot
      # error. The result also builds its own messages, so a stubbed guess in
      # the engine's specs formats exactly like a real one.
      Result = Data.define(:specs, :unmatched, :subjectless, :changed, :hints) do
        # The stop-before-boot usage error: names each expected spec and the
        # ways out as an append-only instruction - never a reconstructed
        # command, which could carry a hostile ref or a wrong source scope.
        def unmatched_message
          pairs = unmatched.map { |file| "#{file} (expected #{hints.fetch(file)})" }
          "no spec found for #{pairs.join(', ')}, so nothing ran. Re-run the same command with --test " \
            "followed by your existing spec paths, or append --all to use the whole suite without " \
            "changing the source scope."
        end

        # Why the subjectless files needed no spec.
        def subjectless_message(since:)
          detail = since ? "no changed mutation subjects" : "no mutation subjects"
          "inferred specs: no spec is required for #{subjectless.join(', ')}: they have #{detail}"
        end

        # The warning for a guess-scoped run: the guessed specs now stand as
        # explicit tests, with the cross-file coverage caveat that brings.
        def scope_message(since:)
          what = since ? "a changed file" : "a source file"
          "inferred specs: running only #{specs.join(', ')}. A spec that reaches " \
            "#{what} only through another file does not run, so a mutant only it would kill can " \
            "survive, and a line no inferred spec executes is reported as NoCoverage"
        end
      end

      SOURCE_ROOTS = %w[lib app].freeze

      def initialize(config, diagnostics: nil)
        @diagnostics = diagnostics
        @root = File.realpath(config.root)
        @config = config
      end

      def call
        @config["since"] ? call_diff : call_all
      end

      # Subject-scoped inference (--subject runs): only the named subjects'
      # files need a guessed spec; every one of them has a subject by
      # construction, so there is no subjectless bucket. With --since the
      # diff narrows the scope further: a named subject whose file is
      # unchanged, whose changed lines sit in other methods, or whose change
      # is comment or formatting only is out of scope and needs no spec.
      def call_for(files, patterns = [])
        files = effective_subject_files(files, patterns) if @config["since"]
        guesses = files.to_h { |file| [file, guess_for(file)] }
        result(guesses, [], files.size)
      end

      # specs: existing spec files (relative paths) guessed for the files in
      # scope; unmatched: such files with no guessed spec; subjectless: files
      # with no mutation subject the run checks, which neither need nor get a
      # spec; changed: how many source files are in scope; hints: each
      # unmatched file's conventional spec path.
      def call_diff
        lines_by_file = changed_lines_by_file
        subjectless = subjectless_files(lines_by_file)
        # Only files with a changed mutation subject get a guessed spec: a
        # subjectless file mutates nothing, so its spec would only narrow the
        # run for no reason.
        guesses = lines_by_file.except(*subjectless).to_h { |file| [file, guess_for(file)] }
        result(guesses, subjectless, lines_by_file.size)
      end

      # Without --since every included file is in scope: a file needs its
      # guessed spec unless it holds no mutation subject at all.
      def call_all
        finder = SubjectFinder.new
        guesses = {}
        subjectless = []
        included_files.each do |file|
          if finder.call(File.join(@root, file)).subjects.empty?
            subjectless << file
          else
            guesses[file] = guess_for(file)
          end
        end
        result(guesses, subjectless.sort, guesses.size + subjectless.size)
      end

      private

      # The named subjects' files inside the diff scope: the subject must
      # sit on a changed line and survive the comment/formatting prune,
      # mirroring the run's subject selection.
      def effective_subject_files(files, patterns)
        lines_by_file = changed_lines_by_file
        comparison = UnchangedSyntax.new(Selection::GitDiff.merge_base(@config["since"], root: @root), root: @root)
        finder = SubjectFinder.new
        files.select do |file|
          lines = lines_by_file[file]
          next false unless lines

          finder.call(File.join(@root, file)).subjects.any? do |subject|
            patterns.any? { |pattern| SubjectSelection.match?(subject.id, pattern) } &&
              subject.overlaps_lines?(lines) &&
              !comparison.unchanged?(subject)
          end
        end
      end

      def result(guesses, subjectless, changed)
        unmatched = guesses.select { |_, spec| spec.nil? }.keys
        Result.new(specs: guesses.values.compact.uniq.sort,
                   unmatched: unmatched,
                   subjectless: subjectless,
                   changed: changed,
                   hints: unmatched.to_h { |file| [file, candidates_for(file).first] })
      end

      # Included files relative to the root, sorted for stable output.
      def included_files
        prefix = "#{@root}/"
        @config.included_files.filter_map { |file| file.delete_prefix(prefix) if file.start_with?(prefix) }.sort
      end

      # Changed files that saboteur would mutate, relative to the root, with
      # their changed line numbers.
      def changed_lines_by_file
        included = @config.included_files.to_set
        Selection::GitDiff.changed_lines(@config["since"], root: @root, include: included,
                                                           diagnostics: @diagnostics)
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
      # Pathname#ascend stops above "." for these relative paths.
      def pack_of(file)
        Pathname(file).ascend do |path|
          dir = path.to_s
          return dir if pack_dirs.include?(dir)
        end
        nil
      end

      def pack_dirs
        @pack_dirs ||= Dir.glob("**/package.yml", base: @root).to_set { |path| File.dirname(path) }
      end
    end
  end
end
