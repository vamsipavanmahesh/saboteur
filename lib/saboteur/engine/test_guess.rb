# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "pathname"

module Saboteur
  class Engine
    # The specs that sit next to the mutated source files by
    # naming convention (lib/a/b.rb -> spec/a/b_spec.rb), or the explicit
    # mapping from config/saboteur_custom_map.rb for layouts the convention
    # cannot guess (#369). A guess, not a
    # coverage fact: a spec that only reaches the file through another one
    # is not found. Packwerk packs (a directory with a package.yml) map to the
    # spec directory inside the same pack, and controllers also map to request
    # specs. With --since, only files whose changed lines carry a mutation
    # subject need a guessed spec; without --since, every included file with
    # a mutation subject needs one. A file that needs a spec and has none
    # stops the run before boot.
    # A project with no *_spec.rb anywhere under its root has no RSpec suite
    # at all: a per-file stop would print one line per
    # source file and bury the real problem (#606, sibling of the
    # missing-rspec-core refusal #542). The stop is one line naming it, with
    # a Minitest pointer when test/ exists; --verbose keeps the per-file list.
    module NoSuiteStop
      MINITEST = "no RSpec suite found - saboteur needs RSpec; " \
                 "this project appears to use Minitest (test/), see docs/minitest.md"
      PLAIN = "no RSpec suite found - saboteur needs RSpec; no spec file exists to run, see docs/minitest.md"

      module_function

      # nil when the run should not claim a missing suite: a --subject run
      # already names its expected spec, nothing is unmatched, or a suite
      # exists. The suite can live outside spec/ - rspec_args can point
      # RSpec at another default path - so look under the whole root;
      # claiming "no spec file exists" for such a project is false and
      # drops the --test/--all remedy (#606). :minitest or :plain otherwise.
      def layout(root, unmatched, subject_run)
        return if subject_run || unmatched.empty?

        return unless Dir.glob(File.join(root, "**", "*_spec.rb")).empty?

        File.directory?(File.join(root, "test")) ? :minitest : :plain
      end

      def message(layout, pairs:, verbose: false)
        line = layout == :minitest ? MINITEST : PLAIN
        verbose ? "#{line} Files without a guessed spec: #{pairs.join(', ')}." : line
      end
    end

    class TestGuess
      # hints: unmatched file -> its conventional spec path (which does
      # not exist; that is why the file is unmatched), for the stop-before-boot
      # error. The result also builds its own messages, so a stubbed guess in
      # the engine's specs formats exactly like a real one.
      # changed_specs: spec files the diff adds or changes that run, already
      # in specs; skipped_specs: spec files the diff touches that cannot run,
      # each with the reason.
      Result = Data.define(:specs, :unmatched, :subjectless, :changed, :hints, :changed_specs,
                           :skipped_specs, :out_of_scope, :excluded, :near, :no_suite, :without_map_entry,
                           :referenced, :crowded) do
        def initialize(changed_specs: [], skipped_specs: {}, out_of_scope: [], excluded: [], near: {},
                       no_suite: nil, without_map_entry: [], referenced: {}, crowded: {}, **fields)
          super
        end

        # The stop-before-boot usage error: names each expected spec and the
        # ways out as an append-only instruction - never a reconstructed
        # command, which could carry a hostile ref or a wrong source scope.
        # When the diff deleted the expected spec or added others, it says
        # so: a renamed spec is the usual cause.
        def unmatched_message(verbose: false)
          if no_suite
            return NoSuiteStop.message(no_suite, pairs: unmatched.map { |f| pair_description(f) }, verbose: verbose)
          end

          pairs = unmatched.map { |file| pair_description(file) }
          changed = changed_specs.any? ? " Specs the diff adds or changes: #{names(changed_specs)}." : ""
          # The map is the documented escape hatch for layouts the
          # convention cannot guess - named only for files no entry covers;
          # a file whose own entry broke heard that in the warning (#640).
          mapped = without_map_entry.any? &&
                   " If the layout defeats the naming convention, map #{names(without_map_entry)} by hand in " \
                   "config/saboteur_custom_map.rb (no entry covers it yet)."
          "no spec found for #{pairs.join(', ')}, so nothing ran.#{changed} Re-run the same command with " \
            "one --test per existing spec path, or append --all to use the whole suite without " \
            "changing the source scope.#{mapped}"
        end

        private

        def pair_description(file)
          expected = hints.fetch(file)
          gone = skipped_specs[expected] == DELETED ? ", deleted in the diff" : ""
          found = near.fetch(file, []).any? ? "; found: #{names(near.fetch(file))}" : ""
          crowd = (count = crowded[file]) ? "; #{ReferenceSpecs.crowd_note(count)}" : ""
          "#{Text.display_safe(file)} (expected #{Text.display_safe(expected)}#{gone}#{found}#{crowd})"
        end

        # Repo-controlled names reach CI logs, so each is escaped before it
        # joins a message (#834): a file name may hold a newline.
        def names(list) = list.map { |name| Text.display_safe(name) }.join(", ")

        public

        # The files that had no spec by name and got the specs that read
        # their constants instead (#725 replaces the guess once a map exists).
        def referenced_message = ReferenceSpecs.note(referenced)

        # The spec files the diff touched that do not run, with the reasons.
        def skipped_message
          named = skipped_specs.map { |path, reason| "#{Text.display_safe(path)} (#{reason})" }
          "inferred specs: not running spec files changed in the diff: #{named.join(', ')}"
        end

        # Why the subjectless files needed no spec.
        def subjectless_message(since:)
          detail = since ? "no changed mutation subjects" : "no mutation subjects"
          "inferred specs: no spec is required for #{names(subjectless)}: they have #{detail}"
        end

        # The per-file warning when the run proceeds with the mapped
        # subset (#370): the file's mutants run only against the inferred
        # specs, so lines nothing else covers surface as NoCoverage.
        def unmatched_warning(file)
          "inferred specs: no spec found for #{pair_description(file)}; its mutants run only " \
            "against the inferred specs and a line they miss is reported as NoCoverage"
        end

        # The stop for a --since run whose changed source files all sit outside the
        # include scope (#483): falling back to the whole suite would run the slowest
        # possible suite against zero subjects, so the run refuses and names what the
        # scope hid. Append-only recovery, like unmatched_message: extend include, or
        # name the specs with --test.
        def out_of_scope_message
          named = names(out_of_scope.first(10))
          more = out_of_scope.size - 10
          named += " and #{more} more" if more.positive?
          "no changed source file lies inside the include scope, so nothing ran. " \
            "Changed source files outside it: #{named}. Extend include to cover them, " \
            "or re-run the same command with one --test per existing spec path."
        end

        # Why an empty guess mutates nothing rather than widening the run
        # to the whole suite (#369).
        def no_specs_message(since:)
          return "#{excluded_message}, so there is nothing to mutate" if excluded.any?

          if since
            "inferred specs: no changed file has a mutation subject on its changed lines, " \
              "so there is nothing to mutate"
          else
            "inferred specs: no source file has a mutation subject, so there is nothing to mutate"
          end
        end

        # Why the custom-map-excluded files needed no spec (#369).
        def excluded_message
          "inferred specs: no spec is required for #{names(excluded)}: " \
            "intentionally untested in config/saboteur_custom_map.rb"
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

      def initialize(config, diagnostics: nil, custom_map: nil)
        @diagnostics = diagnostics
        # Retagged losslessly like Config#root, so a join with a UTF-8 git
        # path never mixes encodings whatever the locale tagged it with.
        @root = Text.utf8_identity(File.realpath(config.root))
        @config = config
        @custom_map = custom_map || CustomMap.load(config.path("custom_map"), root: config.root)
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
        # A --subject run already knows its suite: the stop names the one
        # expected spec, never the no-suite line (#606 is the full-run flood).
        result(guesses, [], files.size, subject_run: true)
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
        # Nothing in scope: name the changed source the include hid (#483).
        out_of_scope = lines_by_file.empty? ? out_of_scope_source_files : []
        result(guesses, subjectless, lines_by_file.size, out_of_scope: out_of_scope)
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

      # The specs the diff itself adds or changes, when a --since run has
      # any guesses to join them with; empty otherwise.
      def diff_specs(inferred, guesses)
        @config["since"] && guesses.any? ? specs_in_diff(inferred) : { run: [], skipped: {} }
      end

      # Unmatched files no map entry even tries to cover: the stop points
      # those at the map (#640); a file whose own entry broke already heard
      # about it in the guess-time warning.
      def without_map_entry(unmatched)
        unmatched.select { |file| @custom_map.specs_for(file).nil? }
      end

      # Changed specs join only a run that mutates something: with no file
      # in scope there is nothing for them to kill.
      def result(guesses, subjectless, changed, out_of_scope: [], subject_run: false)
        unmatched = guesses.select { |_, specs| specs.nil? }.keys
        excluded = guesses.select { |_, specs| specs == :excluded }.keys.sort
        inferred = guesses.values.grep(Array).flatten
        diff = diff_specs(inferred, guesses)
        unmatched -= covered_by_changed_specs(unmatched, diff[:run])
        unmatched, referenced = split_referenced(unmatched)
        Result.new(specs: (inferred + diff[:run] + referenced.values.flatten).uniq.sort,
                   referenced: referenced,
                   unmatched: unmatched,
                   without_map_entry: without_map_entry(unmatched),
                   subjectless: subjectless,
                   changed: changed,
                   **stop_details(unmatched, diff[:skipped]),
                   changed_specs: diff[:run],
                   skipped_specs: diff[:skipped],
                   out_of_scope: out_of_scope,
                   excluded: excluded,
                   no_suite: NoSuiteStop.layout(@root, unmatched, subject_run))
      end

      # What the stop names for each unmatched file: the spec it expected and
      # the same-named specs elsewhere.
      def stop_details(unmatched, skipped)
        { hints: unmatched.to_h { |file| [file, expected_spec(file, skipped)] },
          near: unmatched.to_h { |file| [file, nearby_specs(file)] }, crowded: @crowded }
      end

      # Changed Ruby files the include scope hides (#483), relative to the
      # root: the diff touched source, but none of it lands inside include.
      # A changed spec is a test, not hidden source; a spec-only diff keeps
      # the whole-suite fallback it always had.
      def out_of_scope_source_files
        included = included_files.to_set
        Selection::GitDiff.changed_paths(@config["since"], root: @root)[:present]
                          .select { |path| path.end_with?(".rb") && !spec?(path) && !included.include?(path) }
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

      # A consolidated spec (claims_spec.rb style) never matches the
      # per-file guess, but when the diff itself changes that spec and the
      # spec reads a constant the unmatched file defines, the file is
      # covered: the spec already runs via changed_specs, so stopping would
      # block a run that had something to kill (#538). A mutable change no
      # changed spec exercises still stops.
      def covered_by_changed_specs(unmatched, changed_specs)
        return [] if unmatched.empty? || changed_specs.empty?

        specs = changed_specs.map { |path| File.join(@root, path) }
        unmatched.select do |file|
          defined_constants(file).any? { |constant| ConstantReads.across(specs, constant).any? }
        end
      end

      # Cold start, no map: the specs that read a constant an unmatched file
      # defines (#538 matching). Only files that would stop the run today; a
      # same-basename spec elsewhere means the user has a spec in mind and
      # the choice is ambiguous: that stop stays, it names the candidates (#658).
      def split_referenced(unmatched)
        referenced = reference_specs(unmatched)
        [unmatched - referenced.keys, referenced]
      end

      def reference_specs(unmatched)
        @crowded = {}
        unmatched = unmatched.select { |file| nearby_specs(file).empty? }
        return {} if unmatched.empty? || suite_files.nil?

        specs = suite_files.select { |path| spec?(path) }
        found = ReferenceSpecs.new(@root, method(:defined_constants)).call(unmatched, specs)
        @crowded = found.crowded
        found.chosen
      end

      # The constants a file defines: owners of its def subjects
      # ("JWT::Claims::DecodeVerifier" from "...#call") and its constant
      # literal subjects. Shaped for ConstantReads, which matches a bare
      # read under the owner's scope or the constant's full path.
      DefinedConstant = Data.define(:name, :owner, :id)

      def defined_constants(file)
        path = File.join(@root, file)
        owners = SubjectFinder.new.call(path).subjects.filter_map { |subject| subject.id.split(/[#.]/).first }
        literals = ConstantSubjectFinder.new.call(path).subjects.map(&:id)
        (owners + literals).uniq.map do |id|
          owner, _, name = id.rpartition("::")
          DefinedConstant.new(name: name.to_sym, owner: owner.empty? ? nil : owner, id: id)
        end
      end

      # The spec the stop names for an unmatched file: a candidate the diff
      # deleted (a renamed request spec is not always the first), else the
      # most specific one.
      def expected_spec(file, skipped)
        candidates = candidates_for(file)
        candidates.find { |path| skipped[path] == DELETED } || candidates.first
      end

      # Existing spec files with the same basename anywhere under the spec
      # root: the stop and the warning point at them so the user can
      # --test without hunting (#370). Bounded; computed only for
      # unmatched files, which are about to stop or warn.
      def nearby_specs(file)
        basename = escape_glob(File.basename(file, ".rb"))
        Dir.glob("spec/**/#{basename}_spec.rb", base: @root)
           .select { |path| File.file?(File.join(@root, path)) }.sort.first(3)
      end

      # A path segment is data, not a pattern: [, ], {, }, ?, * and \ are
      # glob metacharacters and must be escaped to match literally.
      def escape_glob(segment)
        segment.gsub(/[\[\]{}?*\\]/) { |char| "\\#{char}" }
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
      # ways. Valid UTF-8 compares in NFC (unicode_normalize's default);
      # other bytes compare as they are.
      def in_suite?(path)
        suite = suite_files
        suite ? suite.include?(comparable(path)) : false
      end

      def comparable(path)
        path.valid_encoding? ? path.unicode_normalize : path
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
        # A file whose diff only deletes lines has no new code to mutate:
        # the deletion is the change the suite itself covers. Its marked
        # neighbor lines would otherwise demand a spec the file never had
        # (#484). Subject selection reads the same list, so both layers
        # agree: no subject, no mutant, no spec demand. The list is
        # canonical-absolute; the line map's keys are root-relative, so
        # compare in absolute space (a monorepo root below the git
        # toplevel must not silently disable this).
        deletion_only = Selection::GitDiff.deletion_only_files(@config["since"], root: @root)
        lines_by_file.reject do |file, lines|
          # (reject keeps the files WITH a changed subject; subjectless
          # is what remains)
          next false if deletion_only.include?(File.join(@root, file))

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

      # The custom map wins over the naming convention: it exists for the
      # layouts the convention cannot guess (#369). Its entries come back as
      # an array of spec paths, or :excluded for a file the map marks
      # intentionally untested - such a file needs no guessed spec, so it is
      # neither unmatched nor given one. Returns the guessed spec paths, nil
      # when neither the map nor the convention names an existing spec.
      def guess_for(file)
        mapped = @custom_map.specs_for(file)
        return :excluded if mapped == :excluded

        expanded = mapped && expand_mapped(file, mapped)
        return expanded if expanded

        conventional = candidates_for(file).find { |path| File.file?(File.join(@root, path)) }
        return [conventional] if conventional

        unique = unique_suffix_spec(file)
        unique && [unique]
      end

      # A mapped spec can be a glob (expanded against the root) or a regexp
      # backreference filled at match time, and neither is validated to
      # exist when the map loads. Only specs that exist run; the literal
      # glob string never reaches RSpec. When the winning entry's specs all
      # vanish the entry is stale or mistyped: warn and fall through to the
      # naming convention (and, failing that, to the usual stop guidance),
      # instead of dying with a ConfigError and hiding the way out (#640).
      def expand_mapped(file, specs)
        expanded = specs.flat_map do |spec|
          if spec.match?(/[*?\[{]/)
            Dir.glob(File.join(@root, spec)).map { |path| path.delete_prefix("#{@root}/") }
          else
            [spec]
          end
        end
        expanded = expanded.select { |path| File.file?(File.join(@root, path)) }
        return expanded unless expanded.empty?

        shown = specs.first(5).map { |spec| Text.display_safe(spec) }.join(", ")
        shown += ", and #{specs.size - 5} more" if specs.size > 5
        @diagnostics&.warn("fix the custom map entry for #{Text.display_safe(file)}: spec(s) #{shown} match no file")
        nil
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
        # A dashed gem name keeps dashes under lib/ but its specs live under
        # the underscored require name: lib/acts-as-taggable-on/x.rb tests in
        # spec/acts_as_taggable_on/x_spec.rb. The literal name still wins
        # when both exist (#383).
        names = names.flat_map { |name| [name, name.tr("-", "_")] }.uniq
        names = layout_variants(names) if rooted
        names.map { |name| "#{spec_root}/#{name}_spec.rb" }
      end

      # Layouts that mirror less of the source path, after every mirrored
      # guess (#394): a spec/unit/ prefix (shoulda-matchers mirrors below
      # it, #393), directories dropped between the gem namespace and the
      # file (rubocop-ast tests lib/rubocop/ast/node/block_node.rb in
      # spec/rubocop/ast/block_node_spec.rb, #586), the basename at the
      # spec root (pundit), and both together (aasm, #370). Weaker
      # guesses come last: the first candidate that exists wins. A file
      # outside the source roots keeps its literal guess only: dropping
      # directories from a path the roots never anchored would guess any
      # same-named spec.
      def layout_variants(names)
        flat = names.map { |name| name.split("/").last }.uniq
        (names + names.map { |name| "unit/#{name}" } + flattened_below_namespace(names) + flat +
          flat.map { |name| "unit/#{name}" }).uniq
      end

      # Every way to drop mid directories from a name, fewest dropped
      # first: each guess keeps at least the leading namespace segment
      # and the basename, so it stays anchored on the gem namespace and
      # more specific than the bare basename flatten (#586).
      def flattened_below_namespace(names)
        names.flat_map do |name|
          segments = name.split("/")
          (segments.size - 2).downto(1).map do |keep|
            (segments.first(keep) + [segments.last]).join("/")
          end
        end.uniq
      end

      # Rails tests controllers as request specs: spec/requests/users_spec.rb
      # or spec/requests/users_controller_spec.rb for controllers/users_controller.rb.
      def request_names(name)
        return [] unless name.start_with?("controllers/")

        path = name.delete_prefix("controllers/")
        ["requests/#{path}", "requests/#{path.delete_suffix('_controller')}"].uniq
      end

      # The last-resort guess when no named candidate exists (#600): a
      # spec tree can strip directories the convention keeps - aasm tests
      # lib/aasm/core/invokers/proc_invoker.rb in
      # spec/unit/invokers/proc_invoker_spec.rb, dropping the aasm and
      # core segments. The one anchor such a layout keeps is the file's
      # parent directory and basename, so a spec under the spec root
      # ending in that suffix is the guess - but only a unique one: a
      # second match makes the layout ambiguous, and guessing would run
      # the wrong specs, a false verdict worse than the stop, whose
      # near-miss hint names the candidates. Only files under a source
      # root with a real parent directory qualify: a bare basename can
      # collide anywhere, so it stays a near-miss hint.
      def unique_suffix_spec(file)
        pack = pack_of(file)
        stem = file.delete_prefix("#{pack}/").delete_suffix(".rb")
        root_segment, _, name = stem.partition("/")
        return nil unless SOURCE_ROOTS.include?(root_segment) && name.include?("/")

        suffix = name.split("/").last(2).map { |segment| escape_glob(segment) }.join("/")
        spec_root = pack ? "#{pack}/spec" : "spec"
        matches = Dir.glob(File.join(@root, spec_root, "**", "#{suffix}_spec.rb"))
                     .select { |path| File.file?(path) }
                     .map { |path| path.delete_prefix("#{@root}/") }.sort
        matches.one? ? matches.first : nil
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
