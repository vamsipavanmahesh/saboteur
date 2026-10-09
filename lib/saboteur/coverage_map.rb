# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require "digest"
require "fileutils"
require "json"

module Saboteur
  # file:line -> ids of the tests that executed that line.
  #
  # Built once per cache key in a forked child that runs the whole suite and
  # takes a per-test delta with Coverage.result(stop: false, clear: true).
  # Lines executed outside any test (before(:all), before(:suite)) are mapped
  # to every test in the file of the next test that starts.
  class CoverageMap
    FORMAT = 1

    attr_reader :lines, :tests, :build_seconds

    # lines: { "/abs/file.rb" => { 12 => ["id1", "id2"] } }
    def initialize(lines:, tests:, build_seconds: nil)
      @lines = lines
      @tests = tests
      @build_seconds = build_seconds
    end

    def tests_for(subject)
      by_line = lines[File.expand_path(subject.file)]
      return [] unless by_line

      ids = subject.coverage_lines.flat_map { |line| by_line.fetch(line, []) }.uniq
      order = test_order
      ids.sort_by { |id| order.fetch(id, Float::INFINITY) }
    end

    def to_json(*)
      JSON.generate(format: FORMAT, tests: tests, build_seconds: build_seconds,
                    lines: lines.transform_values { |by_line| by_line.transform_keys(&:to_s) })
    end

    def self.from_json(json)
      data = JSON.parse(json)
      raise Error, "coverage map format #{data['format']} is not #{FORMAT}" unless data["format"] == FORMAT

      lines = data["lines"].transform_values { |by_line| by_line.transform_keys(&:to_i) }
      new(lines: lines, tests: data["tests"], build_seconds: data["build_seconds"])
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

    # Collects per-test line deltas while the suite runs. The integration
    # calls test_started / test_finished around every test.
    class Recorder
      def initialize(files)
        @files = Set.new(files.map { |file| CoverageMap.canonical(file) })
        @canonical = Hash.new { |hash, path| hash[path] = CoverageMap.canonical(path) }
        @lines = Hash.new { |hash, file| hash[file] = Hash.new { |by_line, line| by_line[line] = [] } }
        @tests = []
        @tests_by_file = Hash.new { |hash, file| hash[file] = [] }
        @outside = Hash.new { |hash, file| hash[file] = Set.new }
      end

      def start
        Coverage.resume if Coverage.state == :suspended
        Coverage.result(stop: false, clear: true)
      end

      def test_started(id, test_file)
        @tests << id
        @tests_by_file[test_file] << id
        each_hit_line { |file, line| @outside[test_file] << [file, line] }
      end

      def test_finished(id)
        each_hit_line { |file, line| @lines[file][line] << id }
      end

      def result(build_seconds: nil)
        @outside.each do |test_file, hits|
          ids = @tests_by_file[test_file]
          hits.each { |file, line| @lines[file][line] |= ids }
        end
        lines = @lines.transform_values { |by_line| by_line.transform_values(&:uniq) }
        CoverageMap.new(lines: lines, tests: @tests, build_seconds: build_seconds)
      end

      private

      def each_hit_line
        Coverage.result(stop: false, clear: true).each do |path, data|
          file = @canonical[path]
          next unless @files.include?(file)

          counts = data.is_a?(Hash) ? data[:lines] : data
          counts&.each_with_index { |count, index| yield file, index + 1 if count&.positive? }
        end
      end
    end
  end
end
