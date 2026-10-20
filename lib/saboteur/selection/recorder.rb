# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "coverage"
require_relative "coverage_map"
require_relative "../method_calls"

module Saboteur
  module Selection
    # Collects per-test line deltas while the suite runs. The integration
    # calls test_started / test_finished around every test.
    class Recorder
      def initialize(files)
        @files = Set.new(files.map { |file| CoverageMap.canonical(file) })
        @canonical = Hash.new { |hash, path| hash[path] = CoverageMap.canonical(path) }
        @calls = MethodCalls.new(@files, canonical: ->(path) { @canonical[path] })
        @arm_spans = {}
        @lines = hit_table
        @methods = hit_table
        @branches = hit_table
        @outside_branches = per_file { Set.new }
        @tests = []
        @tests_by_file = per_file { [] }
        @outside = per_file { Set.new }
        @outside_methods = per_file { Set.new }
        @durations = {}
        @first_loaders = {}
        @seen = Set.new
      end

      def start
        Coverage.resume if Coverage.state == :suspended
        snapshot = CoverageReads.result(stop: false, clear: true)
        @calls.enable
        snapshot
      end

      def test_started(id, test_file)
        @tests << id
        @tests_by_file[test_file] << id
        each_hit do |file, line, kind|
          @seen << file
          { line: @outside, method: @outside_methods, branch: @outside_branches }.fetch(kind)[test_file] << [file, line]
        end
        @started_at = monotonic
      end

      def test_finished(id)
        @durations[id] = monotonic - @started_at if @started_at
        each_hit do |file, line, kind|
          @first_loaders[file] = id if @seen.add?(file)
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
                        methods: methods, branches: branches, loaded_files: loaded_files,
                        first_loaders: @first_loaders.dup)
      end

      private

      def assign_outside(outside, table)
        outside.each do |test_file, hits|
          ids = @tests_by_file[test_file]
          hits.each { |file, line| table[file][line] |= ids }
        end
      end

      # The arm spans of a branch never change, so the filtering below runs
      # once per branch. Every read walks every branch of every recorded
      # file, and redoing the sibling check each time cost far more than
      # the Coverage read itself (#655).
      def record_branches(file, data)
        data.fetch(:branches, {}).each do |key, arms|
          (@arm_spans[[file, key]] ||= recordable_arms(file, arms, key)).each do |arm, span|
            yield span if arms.fetch(arm).positive?
          end
        end
      end

      def recordable_arms(file, arms, key)
        _kind, _id, *parent_span = key
        spans = arms.keys.map { |(_arm_kind, _arm_id, *span)| span }
        arms.keys.filter_map do |arm|
          _arm_kind, _arm_id, *span = arm
          next if span == parent_span
          # Ruby spans a `when X` arm with a bare `nil` body from the
          # `when` to the case's end, containing the sibling arms.
          # Sibling arms are disjoint by definition, so a containing span
          # is bogus; recording it would let it intersect and narrow
          # selection for edits inside the siblings it swallows.
          next if spans.any? { |other| span != other && contains?(span, other) }

          @branches[file][span] # Keep zero-hit arms as evidence, not as covered code.
          [arm, span]
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
        calls = @calls.pause.drain
        suspended = Coverage.running?
        Coverage.suspend if suspended
        snapshot.each do |path, data|
          file = @canonical[path]
          next unless @files.include?(file)

          # Lines mode (set up by the executable); nil marks a line with no
          # code. An endless def's body never counts a line hit, but its
          # calls count through the method tracer (issue #107).
          data[:lines].each_with_index { |count, index| yield file, index + 1, :line if count&.positive? }
          record_branches(file, data) { |span| yield file, span, :branch }
        end
        calls.each do |path, hits|
          # A file loaded before Coverage started has no line evidence; its
          # calls must not make it look recorded (the preloaded refusal).
          next unless snapshot.key?(path)

          file = @canonical[path]
          hits.to_set(&:first).each { |line| yield file, line, :method }
        end
      ensure
        @calls.resume
        # A test may leave Coverage suspended (an in-process Engine#call
        # does); the next test must still be measured.
        Coverage.resume if Coverage.state == :suspended
      end
    end
  end
end
