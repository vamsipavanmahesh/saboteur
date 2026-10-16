# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require "digest"
require "fileutils"
require "json"
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
      FORMAT = 9

      RAN_AT_LOAD = "ran at load: the code ran while the app loaded; a forked test cannot observe a change here"

      attr_reader :lines, :tests, :build_seconds, :durations, :methods, :load_lines, :branches

      # lines: { "/abs/file.rb" => { 12 => ["id1", "id2"] } }
      # methods: { "/abs/file.rb" => { 12 => ["id1", "id2"] } } keyed by the
      # def's first line; line coverage never counts an endless def's body,
      # so methods carry those subjects (issue #107).
      # durations: { "id1" => seconds }
      def initialize(lines:, tests:, build_seconds: nil, durations: {}, methods: {}, load_lines: {}, branches: {})
        @lines = lines
        @tests = tests
        @build_seconds = build_seconds
        @durations = durations
        @methods = methods
        @load_lines = load_lines
        @branches = branches
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
      def with_load_lines(load_lines)
        self.class.new(lines: lines, tests: tests, build_seconds: build_seconds, durations: durations,
                       methods: methods, load_lines: load_lines, branches: branches)
      end

      # A requested line ran at load but no test later hit it.
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
                      methods: encode.call(methods), load_lines: load_lines,
                      branches: encode_branches(index),
                      durations: tests.map { |id| durations[id]&.round(6) })
      end

      def self.from_json(json)
        data = JSON.parse(json)
        raise Error, "coverage map format #{data['format']} is not #{FORMAT}" unless data["format"] == FORMAT

        tests = data["tests"]
        decode = lambda do |hits|
          hits.transform_values do |by_line|
            by_line.to_h { |line, indexes| [line.to_i, indexes.map { |i| tests.fetch(i) }] }
          end
        end
        durations = tests.zip(data["durations"]).to_h.compact
        load_lines = (data["load_lines"] || {}).transform_values { |list| list.map(&:to_i) }
        new(lines: decode.call(data["lines"]), tests: tests, build_seconds: data["build_seconds"],
            durations: durations, methods: decode.call(data["methods"] || {}), load_lines: load_lines,
            branches: decode_branches(data.fetch("branches", {}), tests))
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

      def self.load(path)
        from_json(Text.utf8_strict(File.read(path))) if File.file?(path)
      rescue JSON::ParserError, Error
        nil
      end

      def save(path)
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.#{Process.pid}.tmp"
        File.write(tmp, to_json)
        File.rename(tmp, path)
      end

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

      def sort_test_ids(ids)
        order = test_order
        ids.sort_by { |id| [durations.fetch(id, Float::INFINITY), order.fetch(id, Float::INFINITY)] }
      end

      def test_order
        @test_order ||= tests.each_with_index.to_h
      end
    end
  end
end
