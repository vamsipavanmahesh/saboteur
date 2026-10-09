# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require_relative "coverage_map"

module Saboteur
  module Selection
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
        @durations = {}
      end

      def start
        Coverage.resume if Coverage.state == :suspended
        Coverage.result(stop: false, clear: true)
      end

      def test_started(id, test_file)
        @tests << id
        @tests_by_file[test_file] << id
        each_hit_line { |file, line| @outside[test_file] << [file, line] }
        @started_at = monotonic
      end

      def test_finished(id)
        @durations[id] = monotonic - @started_at if @started_at
        each_hit_line { |file, line| @lines[file][line] << id }
      end

      def result(build_seconds: nil)
        @outside.each do |test_file, hits|
          ids = @tests_by_file[test_file]
          hits.each { |file, line| @lines[file][line] |= ids }
        end
        lines = @lines.transform_values { |by_line| by_line.transform_values(&:uniq) }
        CoverageMap.new(lines: lines, tests: @tests, build_seconds: build_seconds, durations: @durations)
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Coverage is suspended while the delta is processed, so the recorder's
      # own work (and anything it calls) is never attributed to a test.
      def each_hit_line
        snapshot = Coverage.result(stop: false, clear: true)
        suspended = Coverage.running?
        Coverage.suspend if suspended
        snapshot.each do |path, data|
          file = @canonical[path]
          next unless @files.include?(file)

          # Lines mode (set up by the executable); nil marks a line with no code.
          data[:lines].each_with_index { |count, index| yield file, index + 1 if count&.positive? }
        end
      ensure
        Coverage.resume if suspended
      end
    end
  end
end
