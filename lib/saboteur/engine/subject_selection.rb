# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../text"
require_relative "../constant_subject"
require_relative "../constant_subject_finder"
require_relative "../constant_reads"

module Saboteur
  class Engine
    # The subjects to mutate: every def in the included files, narrowed by
    # --subject patterns and by --since (methods with a changed line).
    class SubjectSelection
      # Lines changed since the --since ref, by file; nil without --since.
      attr_reader :changed_lines

      def initialize(config, diagnostics)
        @config = config
        @diagnostics = diagnostics
        @root = File.realpath(config.root)
      end

      def select(files)
        @files = files
        subjects = find(files)
        if @config["since"]
          @changed_lines = changed_lines_map
          subjects += constant_subjects
        end
        @discovered = subjects
        subjects = by_pattern(subjects, @config["subjects"]) if @config["subjects"].any?
        subjects = by_change(subjects, @config["since"]) if @config["since"]
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
          InlineSuppression.new(file, File.read(file))
          parsed = finder.call(file)
          @diagnostics.record_discovery_failure(file, reason: "invalid_file_syntax") unless parsed.errors.empty?
          parsed.errors.first(1).each do |message|
            @diagnostics.warn("#{file.delete_prefix("#{@root}/")} does not parse: #{message}")
          end
          parsed.subjects
        end
      end

      def by_pattern(subjects, patterns)
        patterns.each do |pattern|
          next if subjects.any? { |subject| self.class.match?(subject.id, pattern) }

          @diagnostics.warn("--subject #{pattern} matches no subject (patterns are names like " \
                            "Klass, Klass#meth or Klass.meth, not globs)")
        end
        subjects.select { |subject| patterns.any? { |pattern| self.class.match?(subject.id, pattern) } }
      end

      def by_change(subjects, ref)
        changed = changed_subjects(subjects)
        warn_changed_files_without_subjects
        warn_excluded_changed_files
        drop_unchanged_syntax(changed, ref)
      end

      # Lines changed since the --since ref, canonicalized by file.
      def changed_lines_map
        Selection::GitDiff.changed_lines(@config["since"], root: @root, include: @files.to_set,
                                                           diagnostics: @diagnostics)
                          .transform_keys { |file| Selection::CoverageMap.canonical(file) }
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
            warn_unsupported_constant(found) if found.overlaps_lines?(lines)
          end
          accepted = parsed.subjects.select { |subject| subject.overlaps_lines?(lines) }
          subjects.concat(reject_hazardous_file(file, accepted))
        end
        subjects
      end

      # A constant mutant re-evaluates the whole file with the literal
      # changed. A file that runs side-effecting code at load (FileUtils.rm,
      # system, a backtick) would run it again on every mutant, outside the
      # method hazard guard: skip its constants and say how to opt back in
      # (#319).
      def reject_hazardous_file(file, subjects)
        return subjects if subjects.empty?

        hazards = MutationSource::HazardGuard.new(@config["hazard"])
                                             .load_time_hazards(Prism.parse(File.binread(file)).value)
        return subjects if hazards.empty?

        path = file.delete_prefix("#{@root}/")
        @diagnostics.warn("--since: constant subject(s) in #{path} are not mutated: the file runs " \
                          "side-effecting code at load (#{hazards.first(2).join(', ')}) and a constant " \
                          "mutant re-evaluates the whole file. Move the literal into its own file to " \
                          "mutate it.")
        []
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
          if subject.consumer_lines.empty? && reads.any? { |file, r| file != subject.file && r.load.any? }
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
      # paths that exist.
      def spec_files
        @config["tests"].map { |file| File.absolute_path(file, @root) }
                        .select { |file| file.end_with?(".rb") && File.file?(file) }
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
        @diagnostics.warn("--since: #{unmatched.size} changed Ruby file(s) have no subjects covering " \
                          "the changed lines, so nothing is mutated from them: #{names}#{more}. The " \
                          "file may not parse, or every change may sit outside a method.")
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

      # A method whose only changes are comments, blank lines or spacing has
      # nothing new to test.
      def drop_unchanged_syntax(subjects, ref)
        return subjects if subjects.empty?

        comparison = UnchangedSyntax.new(Selection::GitDiff.merge_base(ref, root: @root), root: @root)
        same, kept = subjects.partition { |subject| comparison.unchanged?(subject) }
        report_unchanged_syntax(same)
        kept
      end

      def report_unchanged_syntax(subjects)
        return if subjects.empty?

        names = subjects.first(5).map(&:id).join(", ")
        more = subjects.size > 5 ? ", ..." : ""
        @diagnostics.inform("#{subjects.size} changed subject(s) differ only in comments or formatting, " \
                            "so they are skipped: #{names}#{more}")
      end
    end
  end
end
