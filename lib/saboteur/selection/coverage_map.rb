# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require "digest"
require "fileutils"
require "json"
require "securerandom"
require_relative "../text"

module Saboteur
  module Selection
    # file:line -> ids of the tests that executed that line.
    #
    # Built once per cache key in a forked child that runs the whole suite and
    # takes a per-test delta with Coverage.result(stop: false, clear: true).
    # Lines executed outside any test (before(:all), before(:suite)) are mapped
    # to every test in the file of the next test that starts. Each test's
    # duration is recorded so selected tests can run fastest first.
    class CoverageMap
      MAX_BYTES = 64 * 1024 * 1024
      FORMAT = 11

      RAN_AT_LOAD = "ran at load: the code ran while the app loaded; a forked test cannot observe a change here"
      PRELOADED = "loaded before coverage started"

      attr_reader :lines, :tests, :build_seconds, :loaded_files, :durations, :methods, :load_lines, :load_methods,
                  :branches, :preloaded, :first_loaders

      # lines: { "/abs/file.rb" => { 12 => ["id1", "id2"] } }
      # methods: { "/abs/file.rb" => { 12 => ["id1", "id2"] } } keyed by the
      # def's first line; line coverage never counts an endless def's body,
      # so methods carry those subjects (issue #107).
      # durations: { "id1" => seconds }
      # first_loaders: { "/abs/file.rb" => "id1" } the test during which a file
      # first showed any hit, which is when a lazy require ran its load-time
      # lines; nil when the map predates the record, so nothing is known.
      def initialize(lines:, tests:, build_seconds: nil, durations: {}, methods: {}, load_lines: {}, load_methods: {},
                     branches: {}, loaded_files: nil, preloaded: [], first_loaders: nil)
        @first_loaders = first_loaders
        @lines = lines
        @tests = tests
        @build_seconds = build_seconds
        @durations = durations
        @methods = methods
        @load_lines = load_lines
        @load_methods = load_methods
        @branches = branches
        @loaded_files = loaded_files || []
        @preloaded = preloaded.to_set { |file| CoverageMap.canonical(file) }
      end

      # Source files the given tests touched, sorted and deduped: the
      # dependency set a cached verdict must watch (#197). The inversion is
      # built once per map and memoized.
      def files_for(test_ids)
        by_test = @files_by_test ||= invert_coverage
        test_ids.flat_map { |id| by_test.fetch(id, []) }.uniq.sort
      end

      # { test id => [source files it touched] }, built once per map. Line
      # and method coverage both count: an endless def's file has only
      # method evidence (#107), and a change there must still invalidate (#344).
      def invert_coverage
        [lines, methods].each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |hits, acc|
          hits.each { |file, line_tests| line_tests.each_value { |ids| ids.each { |id| acc[id] << file } } }
        end
      end

      # Files that ran while the app loaded: their state precedes every
      # test, so every cached verdict depends on them (#344).
      def boot_files
        load_lines.keys.sort
      end

      def tests_for(subject)
        return tests_for_constant(subject) if subject.is_a?(ConstantSubject)

        tests = tests_for_lines(subject.file, subject.coverage_lines)
        return tests unless tests.empty?

        by_method = methods[CoverageMap.canonical(subject.file)]
        return [] unless by_method

        span = subject.start_line..subject.end_line
        ids = by_method.flat_map { |line, method_ids| span.cover?(line) ? method_ids : [] }.uniq
        sort_test_ids(ids)
      end

      # A constant is observable wherever it is read: the tests that ran
      # any read of it, across every file the consumer scan found (#306).
      # A read inside an endless def has no line coverage, so its def's
      # per-test method-call counter stands in (#319).
      def tests_for_constant(subject)
        ids = subject.consumer_lines.flat_map { |file, lines| tests_for_lines(file, lines) }
        ids += subject.consumer_defs.flat_map do |file, def_lines|
          by_method = methods[CoverageMap.canonical(file)]
          by_method ? def_lines.flat_map { |line| by_method.fetch(line, []) } : []
        end
        sort_test_ids(ids.uniq)
      end

      # Attach the parent's boot counters without losing the child's method coverage.
      def with_load_lines(load_lines, load_methods = {})
        self.class.new(lines: lines, tests: tests, build_seconds: build_seconds, durations: durations,
                       methods: methods, load_lines: load_lines, load_methods: load_methods, branches: branches,
                       loaded_files: loaded_files, first_loaders: first_loaders)
      end

      # Files that loaded before Coverage.start (gemspec require, RUBYOPT
      # -r): they can never carry hits, so their subjects are reported as
      # loaded before coverage started instead of no coverage.
      def with_preloaded(paths)
        self.class.new(lines: lines, tests: tests, build_seconds: build_seconds, durations: durations,
                       methods: methods, load_lines: load_lines, load_methods: load_methods, branches: branches,
                       loaded_files: loaded_files, preloaded: paths, first_loaders: first_loaders)
      end

      def preloaded?(file)
        preloaded.include?(CoverageMap.canonical(file))
      end

      # A def the boot called (a def-time macro's class-body caller, say)
      # and no test or hook called again: re-evaluating it post-boot
      # changes nothing a selected test can observe, because closure
      # consumers captured the pristine definition (#409).
      def called_only_at_load?(file, line)
        file = CoverageMap.canonical(file)
        load_methods.fetch(file, []).include?(line) && methods.fetch(file, {}).fetch(line, []).empty?
      end

      # A requested line ran at load but no test later hit it.
      # The boot-once signature (#575): every test is credited with the
      # subject and its lines also ran while the app loaded. The credit is
      # the boot run leaking into cumulative per-test coverage, so mutants
      # of the subject - applied after boot - can all survive even where
      # the suite depends on the method.
      def boot_once?(subject)
        return false if subject.is_a?(ConstantSubject)
        return false unless tests.any? && tests_for(subject).size == tests.size

        boot_credited?(subject.file, subject.coverage_lines)
      end

      # One of the subject's lines ran while the app loaded.
      def boot_credited?(file, line_numbers)
        at_load = load_lines[CoverageMap.canonical(file)]
        return false unless at_load

        line_numbers.any? { |line| at_load.include?(line) }
      end

      def ran_at_load?(file, line_numbers)
        at_load = load_lines[CoverageMap.canonical(file)]
        return false unless at_load

        covered = lines[CoverageMap.canonical(file)] || {}
        line_numbers.any? { |line| at_load.include?(line) && !covered.key?(line) }
      end

      # Tests for the lines of one edit. A branch no test executes keeps its
      # "no coverage" skip, but a subject whose lines never record at all
      # (an endless def) falls back to its method coverage (issue #107).
      def tests_for_edit(subject, line_numbers)
        # An edit to a constant literal is observable at every read of the
        # constant, not on the literal's own (load-time) lines: narrowing
        # by edit lines is meaningless (#306).
        return tests_for(subject) if subject.is_a?(ConstantSubject)

        tests = tests_for_lines(subject.file, line_numbers)
        return tests unless tests.empty?
        return [] unless tests_for_lines(subject.file, subject.coverage_lines).empty?

        tests_for(subject)
      end

      # nil means Ruby supplied no arm evidence for this edit (including &&/||).
      # An empty list means a known arm was never taken. Nested arms intersect.
      def tests_for_branches(subject, edits)
        arms = branches.fetch(CoverageMap.canonical(subject.file), {})
        matching = edits.map do |edit|
          first = position(subject.file_source, edit.start_byte)
          last = position(subject.file_source, edit.end_byte)
          selected = arms.select do |span, ids|
            (span.first(2) <=> first) <= 0 && (last <=> span.last(2)) <= 0 &&
              !ran_before_tests?(subject.file, span, ids)
          end
          selected.values.reduce { |ids, other| ids & other }
        end
        return nil if matching.include?(nil)

        sort_test_ids(matching.flatten.uniq)
      end

      # True when neither boot nor tests recorded included code. Load-only
      # evidence is valid, even though it supplies no judged mutation score.
      def empty?
        [lines, methods, load_lines].all? { |hits| hits.none? { |_file, values| values.any? } }
      end

      # True when none of these files recorded a line hit, a method call, or
      # a load-time hit. The recorder's map also holds the suite's spec
      # files, so whole-map emptiness cannot tell a build that recorded test
      # code only while the included files stayed dark.
      def empty_for?(files)
        wanted = files.map { |file| CoverageMap.canonical(file) }
        [lines, methods, load_lines].all? do |hits|
          wanted.none? { |file| hits[file]&.any? }
        end
      end

      # Tests that executed any of the lines, fastest first (suite order breaks
      # ties), no duplicates. With fail-fast, a mutant is killed by its
      # cheapest killing test.
      # The time the tests took while the map was built, or nil when one of
      # them has no recorded duration.
      def recorded_runtime(test_ids)
        test_ids.sum { |id| durations.fetch(id) { return nil } }
      end

      def tests_for_lines(file, line_numbers)
        by_line = lines[CoverageMap.canonical(file)]
        return [] unless by_line

        sort_test_ids(line_numbers.flat_map { |line| by_line.fetch(line, []) }.uniq)
      end

      # Lines refer to tests by their index in tests, which keeps the cache
      # small for suites with long test ids.
      def to_json(*)
        index = test_order
        encode = lambda do |hits|
          hits.transform_values { |by_line| by_line.to_h { |line, ids| [line.to_s, ids.map { |id| index.fetch(id) }] } }
        end
        JSON.generate(format: FORMAT, tests: tests, build_seconds: build_seconds, lines: encode.call(lines),
                      methods: encode.call(methods), load_lines: load_lines, load_methods: load_methods,
                      branches: encode_branches(index),
                      durations: tests.map { |id| durations[id]&.round(6) }, loaded_files: loaded_files,
                      first_loaders: first_loaders)
      end

      def self.from_json(json)
        data = JSON.parse(json)
        raise Error unless data.is_a?(Hash)
        raise Error, "coverage map format #{data['format']} is not #{FORMAT}" unless data["format"] == FORMAT
        raise Error unless strings?(data["tests"])
        raise Error unless data["durations"].nil? || numbers?(data["durations"])
        raise Error unless data["build_seconds"].nil? || finite?(data["build_seconds"])
        raise Error unless data["loaded_files"].nil? || strings?(data["loaded_files"])

        from_data(data)
      end

      def self.strings?(list)
        list.is_a?(Array) && list.all?(String)
      end

      # Durations hold nil for a test that was not timed.
      def self.numbers?(list)
        list.is_a?(Array) && list.all? { |value| value.nil? || finite?(value) }
      end

      def self.finite?(value)
        value.is_a?(Numeric) && value.finite?
      end

      def self.from_data(data)
        tests = data["tests"]
        decode = lambda do |hits|
          hits.transform_values do |by_line|
            by_line.to_h { |line, indexes| [line.to_i, indexes.map { |i| tests.fetch(i) }] }
          end
        end
        durations = tests.zip(data["durations"] || []).to_h.compact
        new(lines: decode.call(data["lines"]), tests: tests, build_seconds: data["build_seconds"],
            durations: durations, methods: decode.call(data["methods"] || {}),
            load_lines: int_lists(data, "load_lines"), load_methods: int_lists(data, "load_methods"),
            first_loaders: decode_first_loaders(data["first_loaders"], tests),
            branches: decode_branches(data.fetch("branches", {}), tests), loaded_files: data["loaded_files"])
      end

      # Untrusted cache content: only a table of known test ids counts,
      # anything else is "nothing known".
      def self.decode_first_loaders(table, tests)
        return unless table.is_a?(Hash)

        known = tests.to_set
        table.values.all? { |id| known.include?(id) } ? table : nil
      end

      def self.int_lists(data, key)
        (data[key] || {}).transform_values { |list| list.map(&:to_i) }
      end

      def self.decode_branches(branches, tests)
        branches.transform_values do |arms|
          arms.to_h { |span, ids| [span, ids.map { |id| tests.fetch(id) }] }
        end
      end

      # Cache key over every input that can change which test runs which line.
      def self.cache_key(files:, extra:)
        digest = Digest::SHA256.new
        digest << VERSION << "\0" << extra.to_s << "\0"
        files.sort.each do |file|
          digest << file << "\0" << (File.file?(file) ? Digest::SHA256.file(file).hexdigest : "missing") << "\0"
        end
        digest.hexdigest
      end

      def self.canonical(path)
        File.realpath(path)
      rescue SystemCallError
        File.expand_path(path)
      end

      # Every spelling the root can have in $LOADED_FEATURES: a symlink on
      # the root path (macOS /var -> /private/var) gives the same directory
      # both the resolved and the spelled form, and canonical() resolves a
      # loaded feature only while its file exists. Match membership against
      # both, each with a trailing slash so prefix siblings stay out.
      def self.root_prefixes(root)
        [File.realpath(root), File.expand_path(root)].uniq.map { |path| "#{path}/" }
      end

      # The dependency universe a cached verdict watches when coverage
      # cannot speak: every project file the booted process loaded, plus
      # the run's own files (#344).
      def self.loaded_project_files(files, prefixes:)
        $LOADED_FEATURES.filter_map do |file|
          path = Text.utf8_strict(canonical(file))
          path if path.end_with?(".rb") && prefixes.any? { |prefix| path.start_with?(prefix) }
        end | files
      end

      # A cached map is untrusted input (a restored cache can be planted):
      # read only as a regular file, never a symlink or FIFO, under a size
      # cap; anything else is a miss (#427).
      def self.load(path)
        from_json(Text.utf8_strict(slurp(path)))
      rescue JSON::ParserError, Error, SystemCallError, EncodingError, ArgumentError, TypeError, NoMethodError,
             IndexError
        nil
      end

      def self.slurp(path)
        File.open(path, File::RDONLY | File::NONBLOCK | File::NOFOLLOW) do |io|
          raise Error unless io.stat.file?

          text = io.read(MAX_BYTES)
          raise Error unless io.eof?

          text
        end
      end

      def save(path)
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.#{SecureRandom.hex(8)}.tmp"
        # "wx": a planted file or symlink at the temp name is never followed.
        File.open(tmp, "wx", 0o600) { |out| out.write(to_json) }
        File.rename(tmp, path)
      ensure
        FileUtils.rm_f(tmp) if tmp
      end

      # One map from shard maps built over a partition of the suite's spec
      # files (#741). Test ids are file-anchored, so disjoint shards never
      # repeat one - a repeated id means the partition was not disjoint and
      # the merge would silently double-count. Per-test structures merge;
      # line, method and branch evidence unions; load-time and preloaded
      # evidence unions (every shard boots the same app); build_seconds
      # sums the shards' effort, staying nil when no shard recorded one.
      def self.combine(maps)
        raise ArgumentError, "no coverage maps to combine" if maps.empty?

        new(lines: combine_hits(maps.map(&:lines)), methods: combine_hits(maps.map(&:methods)),
            branches: combine_hits(maps.map(&:branches)), tests: combine_tests(maps),
            durations: maps.reduce({}) { |acc, map| acc.merge(map.durations) },
            load_lines: combine_lists(maps.map(&:load_lines)),
            load_methods: combine_lists(maps.map(&:load_methods)),
            loaded_files: maps.flat_map(&:loaded_files).uniq,
            preloaded: maps.flat_map { |map| map.preloaded.to_a },
            build_seconds: maps.map(&:build_seconds).compact.reduce(:+))
      end

      # Disjoint shards never repeat a file-anchored test id; a repeat
      # means the partition was not disjoint and the merge would
      # double-count.
      def self.combine_tests(maps)
        tests = maps.flat_map(&:tests)
        duplicates = tests.tally.select { |_id, count| count > 1 }.keys
        unless duplicates.empty?
          raise ArgumentError, "coverage maps share test ids: #{duplicates.sort.first(3).join(', ')}"
        end

        tests
      end
      private_class_method :combine_tests

      # {file => {line-or-span => ids}} deep-unioned per key.
      def self.combine_hits(hits_list)
        hits_list.each_with_object({}) do |hits, acc|
          hits.each do |file, by_line|
            target = (acc[file] ||= {})
            by_line.each { |line, ids| target[line] = (target[line] || []) | ids }
          end
        end
      end
      private_class_method :combine_hits

      # {file => [lines]} unioned per file, sorted.
      def self.combine_lists(lists)
        lists.each_with_object({}) do |list, acc|
          list.each { |file, lines| acc[file] = ((acc[file] || []) | lines).sort }
        end
      end
      private_class_method :combine_lists

      private

      def encode_branches(index)
        branches.transform_values do |arms|
          arms.map { |span, ids| [span, ids.map { |id| index.fetch(id) }] }
        end
      end

      # An arm whose body the app ran while loading (a def inside an if) has no
      # per-test hits, yet tests ran the lines inside it. Only lines strictly
      # between the arm's first and last line count: the boundary lines can
      # also hold code outside the arm. An arm with no interior line, such as
      # a one-line arm, cannot be told apart, so its empty list still means
      # "not taken".
      def ran_before_tests?(file, span, ids)
        return false unless ids.empty?

        covered = lines[CoverageMap.canonical(file)] || {}
        ((span[0] + 1)...span[2]).any? { |line| covered.key?(line) }
      end

      def position(source, offset)
        prefix = source.byteslice(0, offset).b
        [prefix.count("\n") + 1, offset - ((prefix.rindex("\n") || -1) + 1)]
      end

      # Durations are compared to the millisecond. Two tests within a
      # millisecond of each other swap places from one map build to the next,
      # and with fail-fast the first failing test names a mutant's killer and
      # kill cause, so sub-millisecond noise must not decide the order (#1274).
      # Suite order breaks the tie instead.
      def sort_test_ids(ids)
        order = test_order
        ids.sort_by { |id| [duration_bucket(id), order.fetch(id, Float::INFINITY)] }
      end

      def duration_bucket(id)
        seconds = durations[id]
        seconds ? (seconds * 1000).ceil : Float::INFINITY
      end

      def test_order
        @test_order ||= tests.each_with_index.to_h
      end
    end
  end
end
