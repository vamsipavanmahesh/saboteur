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
        @lines = hit_table
        @methods = hit_table
        @tests = []
        @tests_by_file = per_file { [] }
        @outside = per_file { Set.new }
        @outside_methods = per_file { Set.new }
        @durations = {}
      end

      def start
        Coverage.resume if Coverage.state == :suspended
        Coverage.result(stop: false, clear: true)
      end

      def test_started(id, test_file)
        @tests << id
        @tests_by_file[test_file] << id
        each_hit do |file, line, kind|
          kind == :line ? @outside[test_file] << [file, line] : @outside_methods[test_file] << [file, line]
        end
        @started_at = monotonic
      end

      def test_finished(id)
        @durations[id] = monotonic - @started_at if @started_at
        each_hit do |file, line, kind|
          kind == :line ? @lines[file][line] << id : @methods[file][line] << id
        end
      end

      def result(build_seconds: nil)
        @outside.each do |test_file, hits|
          ids = @tests_by_file[test_file]
          hits.each { |file, line| @lines[file][line] |= ids }
        end
        @outside_methods.each do |test_file, hits|
          ids = @tests_by_file[test_file]
          hits.each { |file, line| @methods[file][line] |= ids }
        end
        lines = @lines.transform_values { |by_line| by_line.transform_values(&:uniq) }
        methods = @methods.transform_values { |by_line| by_line.transform_values(&:uniq) }
        CoverageMap.new(lines: lines, tests: @tests, build_seconds: build_seconds, durations: @durations,
                        methods: methods)
      end

      private

      def hit_table
        Hash.new { |hash, file| hash[file] = Hash.new { |by_line, line| by_line[line] = [] } }
      end

      def per_file(&block)
        Hash.new { |hash, file| hash[file] = block.call }
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Coverage is suspended while the delta is processed, so the recorder's
      # own work (and anything it calls) is never attributed to a test.
      def each_hit
        snapshot = Coverage.result(stop: false, clear: true)
        suspended = Coverage.running?
        Coverage.suspend if suspended
        snapshot.each do |path, data|
          file = @canonical[path]
          next unless @files.include?(file)

          # Lines mode (set up by the executable); nil marks a line with no
          # code. Methods mode keys are [owner, name, start_line, ...]; an
          # endless def's body never counts a line hit, but its calls count
          # here (issue #107).
          data[:lines].each_with_index { |count, index| yield file, index + 1, :line if count&.positive? }
          data[:methods]&.each do |(_owner, _name, start_line, *), count|
            yield file, start_line, :method if count.positive?
          end
        end
      ensure
        Coverage.resume if suspended
      end
    end
  end
end
