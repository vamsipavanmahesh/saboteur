# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "recorder"
require_relative "../line_hits"

module Saboteur
  module Selection
    # The Recorder, with line hits from a TracePoint instead of a
    # Coverage.result read around every test (#725). Methods come from the
    # same call tracer. It records no branches, so a map from it has none:
    # not a drop-in for the Coverage recorder until that is designed.
    class TraceRecorder < Recorder
      def initialize(files)
        super
        @line_hits = LineHits.new(@files, canonical: ->(path) { @canonical[path] })
      end

      def start
        Coverage.resume if Coverage.state == :suspended
        snapshot = CoverageReads.result(stop: false, clear: true)
        @line_hits.enable
        @calls.enable
        snapshot
      end

      # Lines and methods are exact per test. Branches have no TracePoint
      # event, so Coverage is read once per spec file instead of once per
      # test: the delta read when the next file's first test starts goes to
      # every test of the file that just ran and to every test of the file
      # starting. A branch can therefore be credited to a few more tests than
      # ran it, never fewer, so selection only widens.
      def test_started(id, test_file)
        flush_branches(test_file) unless test_file == @branch_file
        @branch_file = test_file
        super
      end

      def result(**)
        flush_branches(nil)
        super
      end

      private

      def flush_branches(next_file)
        hits = read_branches
        [@branch_file, next_file].compact.each do |test_file|
          hits.each { |file, span| @outside_branches[test_file] << [file, span] }
        end
      end

      def read_branches
        @line_hits.pause
        @calls.pause
        snapshot = CoverageReads.result(stop: false, clear: true)
        Coverage.suspend if Coverage.running?
        hits = []
        snapshot.each do |path, data|
          file = @canonical[path]
          record_branches(file, data) { |span| hits << [file, span] } if @files.include?(file)
        end
        hits
      ensure
        Coverage.resume if Coverage.state == :suspended
        @line_hits.resume
        @calls.resume
      end

      # Both tracers are paused while the delta is processed, so the
      # recorder's own work is never attributed to a test.
      def each_hit
        lines = @line_hits.pause.drain
        calls = @calls.pause.drain
        lines.each_pair { |file, numbers| numbers.each { |line| yield @canonical[file], line, :line } }
        calls.each_pair { |path, hits| hits.to_set(&:first).each { |line| yield @canonical[path], line, :method } }
      ensure
        @line_hits.resume
        @calls.resume
      end
    end
  end
end
