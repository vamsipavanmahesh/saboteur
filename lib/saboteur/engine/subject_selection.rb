# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../text"
require_relative "../constant_subject"
require_relative "../constant_subject_finder"
require_relative "../attribute_finder"
require_relative "../constant_reads"

module Saboteur
  class Engine
    # The subjects to mutate: every def in the included files, narrowed by
    # --subject patterns and by --since (methods with a changed line).
    class SubjectSelection
      # Lines changed since the --since ref, by file; nil without --since.
      attr_reader :changed_lines
      # The changed lines minus layout-only ones (#313): the lines that
      # narrow a changed method's fine-grained mutants.
      attr_reader :behavior_lines

      def initialize(config, diagnostics, test_files: nil, custom_map: nil)
        @config = config
        @diagnostics = diagnostics
        @root = File.realpath(config.root)
        @test_files = test_files
        @custom_map = custom_map || CustomMap.load(config.path("custom_map"), root: config.root)
      end

      def select(files)
        @files = files
        subjects = find(files)
        if @config["since"]
          @changed_lines, @behavior_lines = changed_line_maps
          subjects += constant_subjects
        end
        @discovered = subjects
        warn_unmatched_whole_file(subjects) if @config["since"]
        subjects = by_pattern(subjects, @config["subjects"]) if @config["subjects"].any?
        subjects = by_change(subjects, @config["since"]) if @config["since"]
        subjects = drop_intentionally_untested(subjects)
        attach_consumers(subjects)
      end

      # "Klass#meth", "Klass.meth", or a namespace prefix ("Klass", "A::B").
      def self.match?(id, pattern)
        id == pattern || %w[# . ::].any? { |separator| id.start_with?("#{pattern}#{separator}") }
      end

      # The files (absolute paths) holding a subject matching any pattern,
      # returned relative to root. --subject inference guesses specs for
      # exactly these, so one unrelated spec-less file cannot block a
      # one-method run. With --since, constant literal subjects count too:
      # a file holding only the named constant otherwise falls out of
      # inference and runs the whole suite (#319).
      def self.files_matching(root, files, patterns, config = { "since" => nil })
        include_constants = !config["since"].nil?
        finder = SubjectFinder.new
        constant_finder = ConstantSubjectFinder.new if include_constants
        prefix = "#{root}/"
        files.filter_map do |file|
          parsed = finder.call(file)
          matching = parsed.subjects.any? do |subject|
            patterns.any? { |pattern| match?(subject.id, pattern) }
          end
          if !matching && constant_finder
            matching = constant_finder.call(file).subjects.any? do |subject|
              patterns.any? { |pattern| match?(subject.id, pattern) }
            end
          end
          file.delete_prefix(prefix) if matching
        end.sort
      end

      private

      def find(files)
        finder = SubjectFinder.new
        files.flat_map do |file|
          source = File.read(file)
          InlineSuppression.new(file, source)
          parsed = finder.call(file)
          unless parsed.errors.empty?
            if source.include?("<%")
              @diagnostics.record_erb_template_skip(file, root: @root)
            else
              @diagnostics.record_discovery_failure(file, reason: "invalid_file_syntax")
              parsed.errors.first(1).each do |message|
                @diagnostics.warn("#{file.delete_prefix("#{@root}/")} does not parse: #{message}")
              end
            end
          end
          parsed.subjects
        end
      end

      def by_pattern(subjects, patterns)
        missed = patterns.reject do |pattern|
          subjects.any? { |subject| self.class.match?(subject.id, pattern) }
        end
        missed.each do |pattern|
          @diagnostics.warn(missed_pattern_message(pattern))
        end
        # A total miss is a typo: refuse instead of a green zero-subject
        # summary (#379). A partial miss runs, but the matched count is
        # on the record.
        raise ConfigError, total_miss_message(missed) if missed.size == patterns.size

        if missed.any?
          @diagnostics.warn("#{patterns.size - missed.size} of #{patterns.size} --subject patterns matched")
        end
        subjects.select { |subject| patterns.any? { |pattern| self.class.match?(subject.id, pattern) } }
      end

      # The refusal when every pattern missed (#379). A pattern naming an
      # attribute-macro method gets the real reason - the method exists but
      # has no body to mutate (#373) - instead of the pattern-format hint.
      def total_miss_message(missed)
        if missed.all? { |pattern| attribute_macro_for(pattern) }
          return missed.map { |pattern| missed_pattern_message(pattern) }.join("; ")
        end

        "--subject #{missed.join(', ')} matches no subject (patterns are names like " \
          "Klass, Klass#meth or Klass.meth, not globs)"
      end

      # Why one missed pattern matched nothing: when it names a method an
      # attribute macro generated, say so (#373); otherwise the pattern
      # itself is suspect.
      def missed_pattern_message(pattern)
        macro = attribute_macro_for(pattern)
        return "--subject #{pattern} is defined by #{macro} and has no body to mutate" if macro

        "--subject #{pattern} matches no subject (patterns are names like " \
          "Klass, Klass#meth or Klass.meth, not globs)"
      end

      # The attribute macro that generated the method a pattern names, if
      # any. The files are parsed for macros once, only when a pattern
      # missed.
      def attribute_macro_for(pattern)
        attributes = @attributes ||= @files.flat_map { |file| AttributeFinder.new.call(file) }
        attributes.find { |found| found.id == pattern }&.macro
      end

      def by_change(subjects, ref)
        changed = changed_subjects(subjects)
        warn_changed_files_without_subjects
        warn_excluded_changed_files
        drop_unchanged_syntax(changed, ref)
      end

      # Lines changed since the --since ref, and their behavior-only
      # subset, canonicalized by file.
      def changed_line_maps
        maps = Selection::GitDiff.line_maps(@config["since"], root: @root, include: @files.to_set,
                                                              diagnostics: @diagnostics)
        # A deletion-only file yields no subject and no fine-grained mutant
        # (#484); TestGuess reads the same list, so inference never demands
        # a spec for it either.
        canonical = ->(map) { map.transform_keys { |file| Selection::CoverageMap.canonical(file) } }
        changed = canonical.call(maps.changed)
        # Deleted-subject discovery (#466) probes every changed file,
        # including the deletion-only ones stripped below for scope (#484).
        @raw_changed_files = changed.keys
        return [changed, canonical.call(maps.behavior)] if changed.empty?

        # deletion_only_files returns canonical-absolute paths, the same
        # space as the canonical map keys in any project-root layout.
        deletion_only = Selection::GitDiff.deletion_only_files(@config["since"], root: @root)
        [changed.except(*deletion_only), canonical.call(maps.behavior).except(*deletion_only)]
      end

      # Changed entries of a constant hash or array literal are behavior
      # changes no method owns (#306): the constant joins the diff scope as
      # a subject, and the diff scope narrows its mutants to the changed
      # entries. A changed constant assignment of an unsupported form is
      # named, so a clean method score never implies it was tested.
      def constant_subjects
        finder = ConstantSubjectFinder.new
        files_by_canonical = @files.to_h do |file|
          [Selection::CoverageMap.canonical(Text.utf8_identity(file)), file]
        end
        subjects = []
        @changed_lines.each do |canonical, lines|
          file = files_by_canonical[canonical]
          next unless file && canonical.end_with?(".rb")

          parsed = finder.call(file)
          parsed.unsupported.each do |found|
            next unless found.overlaps_lines?(lines)

            warn_unsupported_constant(found)
            constant_warned_files << canonical
          end
          accepted = parsed.subjects.select { |subject| subject.overlaps_lines?(lines) }
          subjects.concat(admit_replayable_file(file, accepted, canonical))
        end
        subjects
      end

      # A constant mutant re-evaluates the whole file with the literal
      # changed, so whatever the file runs at load runs again on every
      # mutant, outside the method hazard guard. saboteur only replays
      # files whose load-time code it can vet (requires, pure defs,
      # class/module nesting, literal assignments) and that trip no hazard
      # denylist entry; anything else - a helper call, a registration, a
      # write to disk - needs the explicit whole_file opt-in, which says
      # the user accepts the replay (#319). Passing the vet is not a safety
      # proof; it only means no unrecognized code runs at load.
      def admit_replayable_file(file, subjects, canonical)
        opted_in, rest = subjects.partition { |subject| whole_file_opted?(subject) }
        return subjects if rest.empty?

        guard = MutationSource::HazardGuard.new(@config["hazard"])
        root = Prism.parse(File.binread(file)).value
        reasons = (guard.load_time_hazards(root) + guard.unvetted_load_code(root)).uniq
        return subjects if reasons.empty?

        constant_warned_files << canonical
        path = file.delete_prefix("#{@root}/")
        listed = reasons.first(2).join(", ")
        @diagnostics.warn("--since: constant subject(s) in #{path} are not mutated: the file runs code at " \
                          "load (#{listed}) that every constant mutant would run again, and saboteur " \
                          "cannot vet what re-running it does. List the constant in c.whole_file to " \
                          "replay the file anyway, or move the literal into its own file. " \
                          "#{whole_file_id_hint(rest)}")
        opted_in
      end

      # The explicit opt-in for whole-file replay: subject ids or globs,
      # matched like Execution::Reevaluator#whole_file?.
      def whole_file_opted?(subject)
        Array(@config["whole_file"]).any? { |pattern| File.fnmatch?(pattern.to_s, subject.id) }
      end

      # A bare constant name only ever matches a top-level constant's id -
      # never a nested one - so name the exact ids to copy into c.whole_file.
      # The glob example carries its blast radius: it opts in every matching
      # subject project-wide, so the exact id(s) are the safer pick (#635).
      def whole_file_id_hint(subjects)
        ids = subjects.map(&:id)
        named = ids.first(3).map { |id| "\"#{id}\"" }.join(", ")
        named += ", +#{ids.size - 3} more" if ids.size > 3
        "Exact id(s): #{named} (preferred); a glob like \"*#{ids.first.split('::').last}*\" also " \
          "works but opts in every matching subject project-wide."
      end

      # A whole_file pattern that matches nothing silently does nothing (#635):
      # name the pattern and what subject ids look like, so a bare constant
      # name for a nested constant (which never matches its qualified id)
      # stands out. Scoped to this run: a pattern for a file outside the
      # current include set also matches nothing.
      def warn_unmatched_whole_file(subjects)
        @config["whole_file"].each do |pattern|
          next if subjects.any? { |subject| File.fnmatch?(pattern.to_s, subject.id) }

          @diagnostics.warn("--since: whole_file pattern \"#{pattern}\" matches no discovered " \
                            "subject in this run; subject ids look like RULES, A::B::C or A::B#m")
        end
      end

      def warn_unsupported_constant(found)
        path = found.file.delete_prefix("#{@root}/")
        @diagnostics.warn("--since: changed constant #{found.id} in #{path} is not mutated: #{found.reason}. " \
                          "Only hash and array literal entries are mutated.")
      end

      # The tests that can observe a constant mutant are the ones covering a
      # read of the constant; find those reads across the include set AND the
      # specs, which can read a constant directly (#319). A read another file
      # captured at load time (`COPY = A::RULES`) never observes the mutant:
      # it holds the original object. A constant with no observable read at
      # all is dropped with a diagnostic rather than reported Survived.
      def attach_consumers(subjects)
        files = @files + spec_files
        subjects.filter_map do |subject|
          next subject unless subject.is_a?(ConstantSubject)

          reads = ConstantReads.across(files, subject)
          subject.consumer_lines = ConstantReads.observable_lines(reads, subject)
          subject.consumer_defs = reads.transform_values(&:defs)
          if subject.consumer_lines.empty? && reads.any? { |_file, r| r.load.any? }
            path = subject.file.delete_prefix("#{@root}/")
            @diagnostics.warn("--since: changed constant #{subject.id} in #{path} is not mutated: its only " \
                              "reads capture the value at load time in another file, so no test can " \
                              "observe a change to it.")
            next
          end
          subject
        end
      end

      # The specs selected for this run (inferred or explicit), as absolute
      # paths that exist. Directory entries expand to their specs. With no
      # tests named at all (the --all case) the configured integration's
      # loaded spec files answer; the conventional spec tree only stands in
      # when nothing else is known (preview, or an empty suite): a spec can
      # read a constant directly (#319).
      def spec_files
        configured = @config["tests"]
        return configured.flat_map { |entry| expand_spec_entry(entry) }.uniq unless configured.empty?
        return Array(@test_files).uniq unless Array(@test_files).empty?

        expand_spec_entry("spec")
      end

      def expand_spec_entry(entry)
        path = File.absolute_path(entry, @root)
        return Dir.glob(File.join(path, "**", "*_spec.rb")) if File.directory?(path)
        return [] unless path.end_with?(".rb") && File.file?(path)

        [path]
      end

      # subject.file carries the locale tag under a non-UTF-8 locale
      # while the diff keys are UTF-8; retag losslessly before lookup so
      # a non-ASCII path matches by its exact bytes (#231).
      def changed_subjects(subjects)
        subjects.select do |subject|
          key = Selection::CoverageMap.canonical(Text.utf8_identity(subject.file))
          lines = @changed_lines[key]
          lines && subject.overlaps_lines?(lines)
        end
      end

      # Changed files a constant literal warning already covers (#537):
      # the umbrella counts them, but its parse/method guesses do not apply,
      # so it says how many sit in a constant literal instead.
      def constant_warned_files
        @constant_warned_files ||= Set.new
      end

      # A changed Ruby file in scope whose changed lines cover no subject
      # silently contributes nothing to the run (#232): warn, or a typo, an
      # unparseable file or a selection bug passes as a clean selection.
      # Comment-only changes stay quiet: their file matched subjects before
      # drop_unchanged_syntax pruned them, and that prune is reported. A
      # diff touching no included Ruby file is a legitimate empty scope.
      # A file whose only finding is an unsupported or unsafe constant still
      # counts here: the specific diagnostic says why, this says nothing ran
      # (#295 keeps its contract).
      def warn_changed_files_without_subjects
        canonical = ->(file) { Selection::CoverageMap.canonical(Text.utf8_identity(file)) }
        included = @files.map(&canonical)
        matched = changed_subjects(@discovered).map { |subject| canonical.call(subject.file) }
        unmatched = (@changed_lines.keys.select { |file| file.end_with?(".rb") } & included) - matched
        return if unmatched.empty?

        names = unmatched.first(5).map { |file| file.delete_prefix("#{@root}/") }.join(", ")
        more = unmatched.size > 5 ? ", ..." : ""
        note = constant_note(unmatched)
        @diagnostics.warn("--since: #{unmatched.size} changed Ruby file(s) have no subjects covering " \
                          "the changed lines, so nothing is mutated from them: #{names}#{more}. " \
                          "#{subjectless_hint(unmatched)}#{note}")
      end

      # One sentence naming how many umbrella files a constant warning
      # already covers (#537): without it a constant edit the safety bar
      # refuses to mutate reads like an unexplained miss in the umbrella.
      def constant_note(unmatched)
        constants = unmatched.count { |file| constant_warned_files.include?(file) }
        return "" if constants.zero?

        " #{constants} of these #{constants == 1 ? 'file has' : 'files have'} changes inside " \
          "a constant literal that is not mutated (the constant warnings above name them)."
      end

      # Specs land here when one --test carries several paths; the
      # parse/method guesses do not apply to them, so say what happened.
      def subjectless_hint(unmatched)
        return "These are spec files; specs are not mutated - pass them with --test." if
          unmatched.all? { |file| file.end_with?("_spec.rb") }

        embedded = unmatched.select { |file| changed_lines_inside_heredoc?(file) }
        return "The file may not parse, or every change may sit outside a method." if embedded.empty?

        names = embedded.first(5).map { |file| file.delete_prefix("#{@root}/") }.join(", ")
        more = embedded.size > 5 ? ", ..." : ""
        "In #{names}#{more} the changed lines are code embedded in a string (a heredoc, often the " \
          "argument to class_eval/module_eval or a template constant); methods defined by evaluating " \
          "strings are not mutation subjects, so this run cannot see that behavior."
      end

      # A heredoc body is code the static subject walk cannot see: methods
      # defined by class_eval'ing the string, or behavior living in a
      # template constant, exist only when the string is evaluated (#467).
      # Changed lines inside one deserve the specific warning, not the
      # generic parse/method guess. A file that does not parse keeps the
      # generic hint: its problem is named there already.
      def changed_lines_inside_heredoc?(file)
        result = Prism.parse(File.binread(file))
        return false if result.failure?

        spans = heredoc_spans(result.value)
        @changed_lines[file].any? { |line| spans.any? { |span| span.cover?(line) } }
      end

      def heredoc_spans(node, spans = [])
        if (node.is_a?(Prism::StringNode) || node.is_a?(Prism::InterpolatedStringNode)) &&
           node.opening_loc&.slice&.start_with?("<<")
          # The node location of an interpolated string stops at the opening
          # marker; opening through closing covers the whole heredoc body.
          spans << (node.opening_loc.start_line..node.closing_loc.end_line)
        end
        node.compact_child_nodes.each { |child| heredoc_spans(child, spans) }
        spans
      end

      # A changed Ruby file that an include pattern covers but c.exclude
      # removes yields zero candidates with no other sign - this repo's own
      # config excludes lib/saboteur/execution/**, so harness changes once
      # dogfooded as a clean empty scope (#282). Names at most five.
      def warn_excluded_changed_files
        untracked = Selection::UntrackedChanges.paths(@root)
        hits = excluded_territory & (@changed_lines.keys + untracked)
        return if hits.empty?

        names = hits.sort.first(5).map { |file| file.delete_prefix("#{@root}/") }.join(", ")
        more = hits.size > 5 ? ", ..." : ""
        @diagnostics.warn("--since: #{hits.size} changed Ruby file(s) are covered by c.include but removed by " \
                          "c.exclude, so nothing is mutated from them: #{names}#{more}. Narrow or remove the " \
                          "c.exclude entry, or pass the file as a positional source operand (configured " \
                          "excludes are then ignored).")
      end

      # Ruby files an include pattern and an exclude pattern both match,
      # canonicalized the way the diff map keys are.
      def excluded_territory
        canonical = lambda do |file|
          Selection::CoverageMap.canonical(File.expand_path(Text.utf8_identity(file), @config.root))
        end
        territory = @config["include"].flat_map { |pattern| Dir.glob(pattern, base: @config.root) }
        excluded = @config["exclude"].flat_map { |pattern| Dir.glob(pattern, base: @config.root) }
        (territory & excluded).select { |file| file.end_with?(".rb") }.map(&canonical)
      end

      # A file the custom map marks intentionally untested ("path" => []) is
      # never mutated: with no test there is no signal, and a guessed
      # selection would read its empty spec list as "run the whole suite"
      # (#369). The skip is named, never silent.
      def drop_intentionally_untested(subjects)
        kept, dropped = subjects.partition do |subject|
          relative = subject.file.delete_prefix("#{@root}/")
          @custom_map.specs_for(relative) != :excluded
        end
        return subjects if dropped.empty?

        names = dropped.first(5).map(&:id).join(", ")
        more = dropped.size > 5 ? ", ..." : ""
        @diagnostics.inform("#{dropped.size} subject(s) skipped: intentionally untested in " \
                            "config/saboteur_custom_map.rb: #{names}#{more}")
        kept
      end

      # A method whose only changes are comments, blank lines or spacing has
      # nothing new to test. A method the diff deleted is neither: it is
      # reported as deleted, and the neighbours its lines drifted onto are
      # skipped quietly rather than blamed for a comment-only change (#466).
      def drop_unchanged_syntax(subjects, ref)
        # No diff at all: no merge-base lookup, no report.
        return subjects if @raw_changed_files.empty?

        comparison = UnchangedSyntax.new(Selection::GitDiff.merge_base(ref, root: @root), root: @root)
        deleted = comparison.deleted_subjects(@raw_changed_files)
        report_deleted(deleted)
        deleted_files = deleted.to_set { |subject| canonical_path(subject.file) }
        same, kept = subjects.partition { |subject| comparison.unchanged?(subject) }
        report_unchanged_syntax(same.reject { |subject| deleted_files.include?(canonical_path(subject.file)) })
        kept
      end

      # Names at most five, like the other selection notes.
      def report_deleted(deleted)
        return if deleted.empty?

        names = deleted.first(5).map(&:id).join(", ")
        more = deleted.size > 5 ? ", ..." : ""
        verb = deleted.one? ? "subject was" : "subjects were"
        @diagnostics.inform("#{deleted.size} changed #{verb} deleted, nothing to mutate: #{names}#{more}")
      end

      def report_unchanged_syntax(subjects)
        return if subjects.empty?

        names = subjects.first(5).map(&:id).join(", ")
        more = subjects.size > 5 ? ", ..." : ""
        @diagnostics.inform("#{subjects.size} changed subject(s) differ only in comments or formatting, " \
                            "so they are skipped: #{names}#{more}")
      end

      def canonical_path(file)
        Selection::CoverageMap.canonical(Text.utf8_identity(file))
      end
    end
  end
end
