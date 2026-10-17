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
      # changed_specs: spec files the diff adds or changes that run, already
      # in specs; skipped_specs: spec files the diff touches that cannot run,
      # each with the reason.
      Result = Data.define(:specs, :unmatched, :subjectless, :changed, :hints, :changed_specs,
                           :skipped_specs) do
        def initialize(changed_specs: [], skipped_specs: {}, **fields)
          super
        end

        # The stop-before-boot usage error: names each expected spec and the
        # ways out as an append-only instruction - never a reconstructed
        # command, which could carry a hostile ref or a wrong source scope.
        # When the diff deleted the expected spec or added others, it says
        # so: a renamed spec is the usual cause.
        def unmatched_message
          pairs = unmatched.map do |file|
            expected = hints.fetch(file)
            gone = skipped_specs[expected] == DELETED ? ", deleted in the diff" : ""
            "#{file} (expected #{expected}#{gone})"
          end
          changed = changed_specs.any? ? " Specs the diff adds or changes: #{changed_specs.join(', ')}." : ""
          "no spec found for #{pairs.join(', ')}, so nothing ran.#{changed} Re-run the same command with " \
            "--test followed by your existing spec paths, or append --all to use the whole suite without " \
            "changing the source scope."
        end

        # The spec files the diff touched that do not run, with the reasons.
        def skipped_message
          named = skipped_specs.map { |path, reason| "#{path} (#{reason})" }
          "inferred specs: not running spec files changed in the diff: #{named.join(', ')}"
        end

        # Why the subjectless files needed no spec.
        def subjectless_message(since:)
          detail = since ? "no changed mutation subjects" : "no mutation subjects"
          "inferred specs: no spec is required for #{subjectless.join(', ')}: they have #{detail}"
        end

        # The warning for a guess-scoped run: the guessed specs now stand as
        # explicit tests, with the cross-file coverage caveat that brings.
        def scope_message(since:)
          who = since ? SINCE_CAVEAT_SUBJECT : CAVEAT_SUBJECT
          added = changed_specs.any? ? " (changed in the diff: #{changed_specs.join(', ')})" : ""
          "inferred specs: running only #{specs.join(', ')}#{added}. #{who} only through another file " \
            "does not run, so a mutant only it would kill can survive, and a line no inferred spec " \
            "executes is reported as NoCoverage"
        end
      end

      CAVEAT_SUBJECT = "A spec that reaches a source file"
      SINCE_CAVEAT_SUBJECT = "A spec the diff did not change that reaches a changed file"
      SOURCE_ROOTS = %w[lib app].freeze
      DELETED = "deleted in the diff"
      OUTSIDE_SUITE = "not loaded by the configured RSpec suite: its pattern, exclude pattern or default path " \
                      "leaves it out"
      NOT_REGULAR = "not a regular file"

      def initialize(config, diagnostics: nil)
        @diagnostics = diagnostics
        # Retagged losslessly like Config#root, so a join with a UTF-8 git
        # path never mixes encodings whatever the locale tagged it with.
        @root = Text.utf8_identity(File.realpath(config.root))
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
      # scope, plus every spec file the diff adds or changes (#307): a pull
      # request often tests a change through a request or controller spec
      # whose name maps to no changed file. unmatched: such files with no
      # guessed spec; subjectless: files with no mutation subject the run
      # checks, which neither need nor get a spec; changed: how many source
      # files are in scope; hints: each unmatched file's conventional spec
      # path.
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
        constant_finder = ConstantSubjectFinder.new
        files.select do |file|
          lines = lines_by_file[file]
          next false unless lines

          subjects_in(finder, constant_finder, file).any? do |subject|
            patterns.any? { |pattern| SubjectSelection.match?(subject.id, pattern) } &&
              subject.overlaps_lines?(lines) &&
              !comparison.unchanged?(subject)
          end
        end
      end

      # Changed specs join only a run that mutates something: with no file
      # in scope there is nothing for them to kill.
      def result(guesses, subjectless, changed)
        unmatched = guesses.select { |_, spec| spec.nil? }.keys
        inferred = guesses.values.compact
        diff = @config["since"] && guesses.any? ? specs_in_diff(inferred) : { run: [], skipped: {} }
        Result.new(specs: (inferred + diff[:run]).uniq.sort,
                   unmatched: unmatched,
                   subjectless: subjectless,
                   changed: changed,
                   hints: unmatched.to_h { |file| [file, expected_spec(file, diff[:skipped])] },
                   changed_specs: diff[:run],
                   skipped_specs: diff[:skipped])
      end

      # Spec files under the root that the diff since the base adds, changes
      # or deletes. A changed file runs when the configured suite loads it
      # and it is a regular file; RSpec applies its pattern only to the
      # directories it scans, never to a file named as a test, so the suite's
      # own list decides (a fixture under an excluded directory must not
      # run). A changed *_spec.rb that cannot run is named with the reason.
      # An inferred spec is left to inference, which runs it as before
      # #307, so it is neither added again nor reported as skipped.
      def specs_in_diff(inferred)
        paths = Selection::GitDiff.changed_paths(@config["since"], root: @root)
        skipped = paths[:deleted].select { |path| spec?(path) }.to_h { |path| [path, DELETED] }
        candidates = paths[:present] - inferred
        run = candidates.select { |path| spec?(path) || in_suite?(path) }.select do |path|
          reason = unrunnable_reason(path)
          skipped[path] = reason if reason
          reason.nil?
        end
        { run: run, skipped: skipped.sort.to_h }
      end

      # The spec the stop names for an unmatched file: a candidate the diff
      # deleted (a renamed request spec is not always the first), else the
      # most specific one.
      def expected_spec(file, skipped)
        candidates = candidates_for(file)
        candidates.find { |path| skipped[path] == DELETED } || candidates.first
      end

      # lstat, not stat: a symlink can point anywhere, including a spec of
      # another application or a fixture the suite excludes.
      def unrunnable_reason(path)
        return NOT_REGULAR unless File.lstat(File.join(@root, path)).file?
        return @suite_error if suite_files.nil?

        OUTSIDE_SUITE unless in_suite?(path)
      rescue SystemCallError
        NOT_REGULAR
      end

      # macOS git reports a precomposed (NFC) name, while the directory
      # entry RSpec lists can be decomposed (NFD): the same spec spelled two
      # ways. Valid UTF-8 compares in NFC; other bytes compare as they are.
      def in_suite?(path)
        suite = suite_files
        suite ? suite.include?(comparable(path)) : false
      end

      def comparable(path)
        path.valid_encoding? ? path.unicode_normalize(:nfc) : path
      end

      # nil when RSpec cannot list the suite: under a non-UTF-8 locale its
      # own path expansion can mix encodings for a non-ASCII root. A changed
      # spec is then not run, never guessed into the run.
      def suite_files
        return @suite_files if defined?(@suite_files)

        listed = Integration.fetch(@config["integration"]).new(@config).configured_spec_files(@root)
        @suite_files = listed.to_set { |path| comparable(path) }
      rescue EncodingError => e
        @suite_error = "the configured RSpec suite's files could not be listed (#{e.class})"
        @suite_files = nil
      end

      def spec?(path)
        path.end_with?("_spec.rb")
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
        constant_finder = ConstantSubjectFinder.new
        lines_by_file.reject do |file, lines|
          subjects_in(finder, constant_finder, file)
            .select { |subject| subject.overlaps_lines?(lines) }
            .any? { |subject| !comparison.unchanged?(subject) }
        end.keys
      end

      # Def subjects and changed constant literal subjects (#306): both
      # need a spec to run against. Only the --since route asks.
      def subjects_in(finder, constant_finder, file)
        path = File.join(@root, file)
        finder.call(path).subjects + constant_finder.call(path).subjects
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
