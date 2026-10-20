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
        @line_hits.enable
        @calls.enable
        {}
      end

      private

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
