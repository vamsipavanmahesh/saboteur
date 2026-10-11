# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # What a run has to say besides results: warnings for the report, the
    # count of mutations dropped for not parsing, and progress marks.
    class Diagnostics
      MARKS = { killed: ".", survived: "S", timeout: "T", resource_limit: "L", error: "E" }.freeze

      attr_reader :warnings, :invalid_mutations

      def initialize(err)
        @err = err
        @warnings = []
        @invalid_mutations = 0
      end

      def warn(message)
        @warnings << message
      end

      def count_invalid_mutation
        @invalid_mutations += 1
      end

      def inform(message)
        @err.puts("saboteur: #{message}")
      end

      # Prints "<label>: N s elapsed" about every interval seconds while the
      # block runs, so a long phase does not look stuck. The heartbeat thread
      # is always stopped before the caller continues, so it never leaks
      # into a fork.
      def with_progress_heartbeat(label, interval: 30, &block)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        heartbeat = Thread.new do
          loop do
            sleep interval
            inform("#{label}: #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round} s elapsed")
          end
        end
        block.call
      ensure
        heartbeat&.kill
      end

      def progress(result)
        @err.print(MARKS.fetch(result.status, "?"))
        @err.flush
      end
    end
  end
end
