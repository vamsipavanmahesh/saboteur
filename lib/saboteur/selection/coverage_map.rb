# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require "digest"
require "fileutils"
require "json"

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
      FORMAT = 4

      attr_reader :lines, :tests, :build_seconds, :durations, :methods

      # lines: { "/abs/file.rb" => { 12 => ["id1", "id2"] } }
      # methods: { "/abs/file.rb" => { 12 => ["id1", "id2"] } } keyed by the
      # def's first line; line coverage never counts an endless def's body,
      # so methods carry those subjects (issue #107).
      # durations: { "id1" => seconds }
      def initialize(lines:, tests:, build_seconds: nil, durations: {}, methods: {})
        @lines = lines
        @tests = tests
        @build_seconds = build_seconds
        @durations = durations
        @methods = methods
      end

      def tests_for(subject)
        tests = tests_for_lines(subject.file, subject.coverage_lines)
        return tests unless tests.empty?

        by_method = methods[CoverageMap.canonical(subject.file)]
        return [] unless by_method

        span = subject.start_line..subject.end_line
        ids = by_method.flat_map { |line, method_ids| span.cover?(line) ? method_ids : [] }.uniq
        sort_test_ids(ids)
      end

      # Tests for the lines of one edit. A branch no test executes keeps its
      # "no coverage" skip, but a subject whose lines never record at all
      # (an endless def) falls back to its method coverage (issue #107).
      def tests_for_edit(subject, line_numbers)
        tests = tests_for_lines(subject.file, line_numbers)
        return tests unless tests.empty?
        return [] unless tests_for_lines(subject.file, subject.coverage_lines).empty?

        tests_for(subject)
      end

      # True when the build recorded nothing at all: no line hits and no
      # method calls in any included file.
      def empty?
        [lines, methods].all? { |hits| hits.none? { |_file, by_line| by_line.any? } }
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
                      methods: encode.call(methods),
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
        new(lines: decode.call(data["lines"]), tests: tests, build_seconds: data["build_seconds"],
            durations: durations, methods: decode.call(data["methods"] || {}))
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
        from_json(File.read(path)) if File.file?(path)
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
