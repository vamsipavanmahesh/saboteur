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
        @branches = hit_table
        @outside_branches = per_file { Set.new }
        @tests = []
        @tests_by_file = per_file { [] }
        @outside = per_file { Set.new }
        @outside_methods = per_file { Set.new }
        @durations = {}
      end

      def start
        Coverage.resume if Coverage.state == :suspended
        CoverageReads.result(stop: false, clear: true)
      end

      def test_started(id, test_file)
        @tests << id
        @tests_by_file[test_file] << id
        each_hit do |file, line, kind|
          { line: @outside, method: @outside_methods, branch: @outside_branches }.fetch(kind)[test_file] << [file, line]
        end
        @started_at = monotonic
      end

      def test_finished(id)
        @durations[id] = monotonic - @started_at if @started_at
        each_hit do |file, line, kind|
          { line: @lines, method: @methods, branch: @branches }.fetch(kind)[file][line] << id
        end
      end

      def result(build_seconds: nil, loaded_files: [])
        assign_outside(@outside, @lines)
        assign_outside(@outside_methods, @methods)
        assign_outside(@outside_branches, @branches)
        lines = @lines.transform_values { |by_line| by_line.transform_values(&:uniq) }
        methods = @methods.transform_values { |by_line| by_line.transform_values(&:uniq) }
        branches = @branches.transform_values { |arms| arms.transform_values(&:uniq) }
        CoverageMap.new(lines: lines, tests: @tests, build_seconds: build_seconds, durations: @durations,
                        methods: methods, branches: branches, loaded_files: loaded_files)
      end

      private

      def assign_outside(outside, table)
        outside.each do |test_file, hits|
          ids = @tests_by_file[test_file]
          hits.each { |file, line| table[file][line] |= ids }
        end
      end

      def record_branches(file, data)
        data.fetch(:branches, {}).each do |(_kind, _id, *parent_span), arms|
          spans = arms.map { |(_arm_kind, _arm_id, *span), _count| span }
          arms.each do |(_arm_kind, _arm_id, *span), count|
            next if span == parent_span
            # Ruby spans a `when X` arm with a bare `nil` body from the
            # `when` to the case's end, containing the sibling arms.
            # Sibling arms are disjoint by definition, so a containing span
            # is bogus; recording it would let it intersect and narrow
            # selection for edits inside the siblings it swallows.
            next if spans.any? { |other| span != other && contains?(span, other) }

            @branches[file][span] # Keep zero-hit arms as evidence, not as covered code.
            yield span if count.positive?
          end
        end
      end

      # [line, column] pairs compare lexically, like CoverageMap#position.
      # Both endpoints come from one slice per side: a separate slice per
      # comparand would make its size irrelevant on the right-hand side of
      # `<=>` (a prefix decides first), hiding an equivalent mutant.
      def contains?(outer, inner)
        outer_start, inner_start = [outer, inner].map { |span| span.first(2) }
        inner_end, outer_end = [inner, outer].map { |span| span.last(2) }
        (outer_start <=> inner_start) <= 0 && (inner_end <=> outer_end) <= 0
      end

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
        snapshot = CoverageReads.result(stop: false, clear: true)
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
          record_branches(file, data) { |span| yield file, span, :branch }
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
