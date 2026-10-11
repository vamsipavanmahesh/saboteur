# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # What a run has to say besides results: warnings for the report, the
    # count of mutations dropped for not parsing, and progress marks.
    class Diagnostics
      # See progress_heartbeat. Time-gated itself, so the supervisor can
      # call tick on every poll.
      class ProgressHeartbeat
        def initialize(diagnostics, label, interval: 30)
          @diagnostics = diagnostics
          @label = label
          @interval = interval
          @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @last_print = @started
        end

        def tick
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return if now - @last_print < @interval

          @last_print = now
          @diagnostics.inform("#{@label}: #{(now - @started).round} s elapsed")
        end
      end

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

      # A heartbeat for a long phase: the supervisor's wait loop calls tick
      # in the parent after the fork, so no extra thread is ever alive at
      # fork time. Prints "<label>: N s elapsed" about every interval
      # seconds, so a long phase does not look stuck.
      def progress_heartbeat(label, interval: 30)
        ProgressHeartbeat.new(self, label, interval: interval)
      end

      def progress(result)
        @err.print(MARKS.fetch(result.status, "?"))
        @err.flush
      end
    end
  end
end
