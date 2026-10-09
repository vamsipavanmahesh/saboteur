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
      FORMAT = 3

      attr_reader :lines, :tests, :build_seconds, :durations

      # lines: { "/abs/file.rb" => { 12 => ["id1", "id2"] } }
      # durations: { "id1" => seconds }
      def initialize(lines:, tests:, build_seconds: nil, durations: {})
        @lines = lines
        @tests = tests
        @build_seconds = build_seconds
        @durations = durations
      end

      def tests_for(subject)
        tests_for_lines(subject.file, subject.coverage_lines)
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

        ids = line_numbers.flat_map { |line| by_line.fetch(line, []) }.uniq
        order = test_order
        ids.sort_by { |id| [durations.fetch(id, Float::INFINITY), order.fetch(id, Float::INFINITY)] }
      end

      # Lines refer to tests by their index in tests, which keeps the cache
      # small for suites with long test ids.
      def to_json(*)
        index = test_order
        encoded = lines.transform_values do |by_line|
          by_line.to_h { |line, ids| [line.to_s, ids.map { |id| index.fetch(id) }] }
        end
        JSON.generate(format: FORMAT, tests: tests, build_seconds: build_seconds, lines: encoded,
                      durations: tests.map { |id| durations[id]&.round(6) })
      end

      def self.from_json(json)
        data = JSON.parse(json)
        raise Error, "coverage map format #{data['format']} is not #{FORMAT}" unless data["format"] == FORMAT

        tests = data["tests"]
        lines = data["lines"].transform_values do |by_line|
          by_line.to_h { |line, indexes| [line.to_i, indexes.map { |i| tests.fetch(i) }] }
        end
        durations = tests.zip(data["durations"]).to_h.compact
        new(lines: lines, tests: tests, build_seconds: data["build_seconds"], durations: durations)
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

      def test_order
        @test_order ||= tests.each_with_index.to_h
      end
    end
  end
end
